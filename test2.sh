#!/bin/bash

# 颜色定义
C_RESET='\033[0m'
C_RED='\033[31m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_CYAN='\033[36m'

# 路径与常量
NODE_FILE="$HOME/.xray_argo_nodes"
REPO_URL="https://github.com/eooce/python-xray-argo.git"
PROJ_DIR="python-xray-argo"
PY_APP="app.py"

# 依赖检测
function check_deps() {
    echo -e "${C_CYAN}检测依赖...${C_RESET}"
    for cmd in python3 pip3 git curl; do
        if ! command -v $cmd &>/dev/null; then
            echo -e "${C_YELLOW}缺少 $cmd，正在安装...${C_RESET}"
            if command -v apt-get &>/dev/null; then
                sudo apt-get update && sudo apt-get install -y $cmd
            elif command -v yum &>/dev/null; then
                sudo yum install -y $cmd
            else
                echo -e "${C_RED}不支持的包管理器，请手动安装 $cmd${C_RESET}"
                exit 1
            fi
        fi
    done
    python3 -c "import requests" 2>/dev/null || pip3 install --user requests
}

# 下载或更新项目
function fetch_project() {
    if [ ! -d "$PROJ_DIR" ]; then
        git clone "$REPO_URL"
    else
        cd "$PROJ_DIR" && git pull && cd ..
    fi
}

# UUID 生成
function make_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen | tr 'A-Z' 'a-z'
    else
        python3 -c "import uuid;print(uuid.uuid4())"
    fi
}

# 菜单
function show_menu() {
    echo -e "${C_GREEN}========= Xray Argo 一键部署 =========${C_RESET}"
    echo -e "${C_CYAN}1. 极速模式（仅UUID）"
    echo -e "2. 完整模式（全部参数）"
    echo -e "3. 查看节点信息"
    echo -e "0. 退出${C_RESET}"
    read -p "请选择操作: " CHOICE
}

# 节点信息查看
function show_nodes() {
    if [ -f "$NODE_FILE" ]; then
        echo -e "${C_GREEN}------ 节点信息 ------${C_RESET}"
        cat "$NODE_FILE"
    else
        echo -e "${C_RED}未找到节点信息文件${C_RESET}"
    fi
    exit 0
}

# 配置参数交互
function config_params() {
    # $1: mode (fast/full)
    cd "$PROJ_DIR" || exit 1
    cp "$PY_APP" "${PY_APP}.bak.$(date +%s)"
    UUID=$(make_uuid)
    if [ "$1" = "fast" ]; then
        read -p "输入UUID（留空自动生成）: " input_uuid
        [ -n "$input_uuid" ] && UUID="$input_uuid"
        sed -i "s/UUID = .*/UUID = os.environ.get('UUID', '$UUID')/" "$PY_APP"
        sed -i "s/CFIP = .*/CFIP = os.environ.get('CFIP', 'joeyblog.net')/" "$PY_APP"
    else
        read -p "输入UUID（留空自动生成）: " input_uuid
        [ -n "$input_uuid" ] && UUID="$input_uuid"
        sed -i "s/UUID = .*/UUID = os.environ.get('UUID', '$UUID')/" "$PY_APP"
        read -p "节点名称（留空不变）: " NAME
        [ -n "$NAME" ] && sed -i "s/NAME = .*/NAME = os.environ.get('NAME', '$NAME')/" "$PY_APP"
        read -p "服务端口（留空不变）: " PORT
        [ -n "$PORT" ] && sed -i "s/PORT = int.*/PORT = int(os.environ.get('SERVER_PORT') or os.environ.get('PORT') or $PORT)/" "$PY_APP"
        read -p "优选IP（留空默认）: " CFIP
        [ -z "$CFIP" ] && CFIP="joeyblog.net"
        sed -i "s/CFIP = .*/CFIP = os.environ.get('CFIP', '$CFIP')/" "$PY_APP"
        read -p "优选端口（留空不变）: " CFPORT
        [ -n "$CFPORT" ] && sed -i "s/CFPORT = .*/CFPORT = int(os.environ.get('CFPORT', '$CFPORT'))/" "$PY_APP"
        read -p "Argo端口（留空不变）: " ARGO_PORT
        [ -n "$ARGO_PORT" ] && sed -i "s/ARGO_PORT = .*/ARGO_PORT = int(os.environ.get('ARGO_PORT', '$ARGO_PORT'))/" "$PY_APP"
        read -p "配置高级选项? (y/n): " adv
        if [[ "$adv" =~ ^[Yy]$ ]]; then
            read -p "Argo域名（留空不变）: " ARGO_DOMAIN
            [ -n "$ARGO_DOMAIN" ] && sed -i "s/ARGO_DOMAIN = .*/ARGO_DOMAIN = os.environ.get('ARGO_DOMAIN', '$ARGO_DOMAIN')/" "$PY_APP"
            read -p "Argo密钥（留空不变）: " ARGO_AUTH
            [ -n "$ARGO_AUTH" ] && sed -i "s/ARGO_AUTH = .*/ARGO_AUTH = os.environ.get('ARGO_AUTH', '$ARGO_AUTH')/" "$PY_APP"
        fi
    fi
    cd ..
}

#patch_app 防止重复
function patch_app() {
    cd "$PROJ_DIR" || exit 1
    if ! grep -q 'youtube.com' "$PY_APP"; then
        sed -i '/"rules": \[/a\        {\
            "type": "field",\
            "domain": ["youtube.com", "youtu.be"],\
            "outboundTag": "direct"\
        },' "$PY_APP"
    fi
    cd ..
}

# 启动服务
function start_service() {
    cd "$PROJ_DIR" || exit 1
    pkill -f "python3 $PY_APP" 2>/dev/null
    nohup python3 "$PY_APP" > app.log 2>&1 &
    sleep 2
    PID=$(pgrep -f "python3 $PY_APP" | head -1)
    echo -e "${C_GREEN}服务已启动，PID: $PID${C_RESET}"
    cd ..
}

# 等待节点生成
function wait_nodes() {
    cd "$PROJ_DIR" || exit 1
    for i in {1..120}; do
        [ -f ".cache/sub.txt" ] && break
        [ -f "sub.txt" ] && break
        sleep 5
    done
    NODE_DATA=$(cat .cache/sub.txt 2>/dev/null || cat sub.txt 2>/dev/null)
    cd ..
}

# 保存节点信息
function save_info() {
    local uuid="$1"
    local node_data="$2"
    echo "==== Xray Argo 节点信息 ====" > "$NODE_FILE"
    echo "时间: $(date)" >> "$NODE_FILE"
    echo "UUID: $uuid" >> "$NODE_FILE"
    echo "订阅内容:" >> "$NODE_FILE"
    echo "$node_data" | base64 -d 2>/dev/null || echo "$node_data" >> "$NODE_FILE"
    echo "===========================" >> "$NODE_FILE"
    echo -e "${C_GREEN}节点信息已保存到 $NODE_FILE${C_RESET}"
}

# 主流程
check_deps
fetch_project

while true; do
    show_menu
    case "$CHOICE" in
        1) config_params fast; patch_app; start_service; wait_nodes; save_info; break ;;
        2) config_params full; patch_app; start_service; wait_nodes; save_info; break ;;
        3) show_nodes ;;
        0) exit 0 ;;
        *) echo -e "${C_RED}无效选项${C_RESET}" ;;
    esac
done

echo -e "${C_GREEN}部署完成！${C_RESET}"
exit 0
