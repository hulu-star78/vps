#!/bin/bash
# filepath: f:\roger\new_deploy.sh

# 彩色输出常量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 全局变量配置
NODE_INFO_FILE="$HOME/.xray_nodes_info"
PROJECT_DIR="python-xray-argo"
REPO_URL="https://github.com/eooce/python-xray-argo.git"
APP_FILE="app.py"
CACHE_FILE=".cache/sub.txt"
DOWNLOAD_FILE="sub.txt"

# 生成 UUID 函数（依次尝试 uuidgen、python3 和 openssl）
generate_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    elif command -v python3 &>/dev/null; then
        python3 -c "import uuid; print(uuid.uuid4())"
    elif command -v openssl &>/dev/null; then
        openssl rand -hex 16 | sed 's/\(..\)/\1-/g;s/-$//' | tr '[:upper:]' '[:lower:]'
    else
        echo "无法生成 UUID：缺少必要工具"
        exit 1
    fi
}

# 查看节点信息
show_nodes() {
    if [ -f "$NODE_INFO_FILE" ]; then
        echo -e "${GREEN}========== 节点信息 ==========${NC}"
        cat "$NODE_INFO_FILE"
        echo -e "${GREEN}=============================${NC}"
    else
        echo -e "${RED}[错误] 节点信息文件不存在！${NC}"
        echo -e "${YELLOW}请先运行部署脚本生成节点信息${NC}"
    fi
    exit 0
}

# 如果参数为 -v，则直接查看节点信息
if [ "$1" == "-v" ]; then
    show_nodes
fi

clear
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}    Python Xray Argo 部署工具 v2.0    ${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "${BLUE}项目地址：${YELLOW}$REPO_URL${NC}"
echo
echo -e "${GREEN}1. 极速模式（仅更新 UUID 并启动）${NC}"
echo -e "${GREEN}2. 完整配置模式（自定义所有参数）${NC}"
echo -e "${GREEN}3. 查看节点信息${NC}"
echo
read -p "请选择操作 (1/2/3)： " mode_choice

# 如果选择查看节点信息，则调用查看函数，并询问是否重新部署
if [ "$mode_choice" == "3" ]; then
    show_nodes
    read -p "是否重新部署？(y/n): " re_deploy
    if [[ "$re_deploy" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}请选择部署模式：${NC}"
        echo -e "${BLUE}1) 极速模式${NC}"
        echo -e "${BLUE}2) 完整配置模式${NC}"
        read -p "请输入 (1/2)： " mode_choice
    else
        echo -e "${GREEN}退出脚本${NC}"
        exit 0
    fi
fi

# 检查必需的依赖环境（Python3、pip、git）
check_dependencies() {
    echo -e "${BLUE}正在检查依赖环境...${NC}"
    if ! command -v python3 &>/dev/null; then
        echo -e "${YELLOW}Python3 未安装，正在安装...${NC}"
        sudo apt-get update && sudo apt-get install -y python3 python3-pip
    fi
    if ! command -v git &>/dev/null; then
        echo -e "${YELLOW}Git 未安装，正在安装...${NC}"
        sudo apt-get update && sudo apt-get install -y git
    fi
    if ! python3 -c "import requests" &>/dev/null; then
        echo -e "${YELLOW}安装 Python requests 模块...${NC}"
        pip3 install requests
    fi
}

# 拉取或更新项目代码
fetch_project() {
    if [ ! -d "$PROJECT_DIR" ]; then
        echo -e "${BLUE}项目不存在，开始克隆仓库...${NC}"
        git clone "$REPO_URL" "$PROJECT_DIR" || {
            echo -e "${RED}克隆项目失败，请检查网络连接${NC}"
            exit 1
        }
    else
        echo -e "${GREEN}检测到项目目录，跳过克隆${NC}"
    fi
}

# 更新 app.py 中的配置信息(使用 sed 替换对应的配置行)
update_config() {
    local key="$1"
    local new_val="$2"
    local sed_pattern=""
    local sed_repl=""
    case "$key" in
        UUID)
            sed_pattern="UUID = os.environ.get('UUID', '[^']*')"
            sed_repl="UUID = os.environ.get('UUID', '$new_val')"
            ;;
        NAME)
            sed_pattern="NAME = os.environ.get('NAME', '[^']*')"
            sed_repl="NAME = os.environ.get('NAME', '$new_val')"
            ;;
        PORT)
            sed_pattern="PORT = int(os.environ.get('SERVER_PORT') or os.environ.get('PORT') or [0-9]*)"
            sed_repl="PORT = int(os.environ.get('SERVER_PORT') or os.environ.get('PORT') or $new_val)"
            ;;
        CFIP)
            sed_pattern="CFIP = os.environ.get('CFIP', '[^']*')"
            sed_repl="CFIP = os.environ.get('CFIP', '$new_val')"
            ;;
        CFPORT)
            sed_pattern="CFPORT = int(os.environ.get('CFPORT', '[^']*'))"
            sed_repl="CFPORT = int(os.environ.get('CFPORT', '$new_val'))"
            ;;
        ARGO_PORT)
            sed_pattern="ARGO_PORT = int(os.environ.get('ARGO_PORT', '[^']*'))"
            sed_repl="ARGO_PORT = int(os.environ.get('ARGO_PORT', '$new_val'))"
            ;;
        ARGO_DOMAIN)
            sed_pattern="ARGO_DOMAIN = os.environ.get('ARGO_DOMAIN', '[^']*')"
            sed_repl="ARGO_DOMAIN = os.environ.get('ARGO_DOMAIN', '$new_val')"
            ;;
        ARGO_AUTH)
            sed_pattern="ARGO_AUTH = os.environ.get('ARGO_AUTH', '[^']*')"
            sed_repl="ARGO_AUTH = os.environ.get('ARGO_AUTH', '$new_val')"
            ;;
        *)
            return
            ;;
    esac
    sed -i "s/${sed_pattern}/${sed_repl}/" "$APP_FILE"
}

# 开始部署前的准备工作
check_dependencies
fetch_project
cd "$PROJECT_DIR" || exit 1

if [ ! -f "$APP_FILE" ]; then
    echo -e "${RED}[错误] 未在项目目录中找到 $APP_FILE 文件！${NC}"
    exit 1
fi

# 备份配置文件
cp "$APP_FILE" "${APP_FILE}.bak"
echo -e "${YELLOW}已备份 $APP_FILE 为 ${APP_FILE}.bak${NC}"

# 根据不同模式更新配置
if [ "$mode_choice" == "1" ]; then
    echo -e "${BLUE}【极速模式】${NC}"
    current_uuid=$(grep "UUID = " "$APP_FILE" | head -1 | cut -d"'" -f2)
    echo -e "${YELLOW}当前 UUID：$current_uuid${NC}"
    read -p "请输入新的 UUID（留空则自动生成）： " input_uuid
    if [ -z "$input_uuid" ]; then
        input_uuid=$(generate_uuid)
        echo -e "${GREEN}自动生成 UUID：$input_uuid${NC}"
    fi
    update_config UUID "$input_uuid"
    # 默认更新优选 IP 为 joeyblog.net
    update_config CFIP "joeyblog.net"
    echo -e "${GREEN}UUID 及默认优选 IP 已更新${NC}"
elif [ "$mode_choice" == "2" ]; then
    echo -e "${BLUE}【完整配置模式】${NC}"
    # UUID
    current_uuid=$(grep "UUID = " "$APP_FILE" | head -1 | cut -d"'" -f2)
    echo -e "${YELLOW}当前 UUID：$current_uuid${NC}"
    read -p "请输入新的 UUID（留空则自动生成）： " input_uuid
    if [ -z "$input_uuid" ]; then
        input_uuid=$(generate_uuid)
        echo -e "${GREEN}自动生成 UUID：$input_uuid${NC}"
    fi
    update_config UUID "$input_uuid"
    # 节点名称
    current_name=$(grep "NAME = " "$APP_FILE" | head -1 | cut -d"'" -f2)
    echo -e "${YELLOW}当前节点名称：$current_name${NC}"
    read -p "请输入新节点名称（留空保持不变）： " input_name
    if [ -n "$input_name" ]; then
        update_config NAME "$input_name"
    fi
    # 服务端口
    port_val=$(grep "PORT = int" "$APP_FILE" | grep -o "or [0-9]*" | cut -d" " -f2)
    echo -e "${YELLOW}当前服务端口：$port_val${NC}"
    read -p "请输入新的服务端口（留空保持不变）： " input_port
    if [ -n "$input_port" ]; then
        update_config PORT "$input_port"
    fi
    # 优选 IP/域名
    current_cfip=$(grep "CFIP = " "$APP_FILE" | cut -d"'" -f2)
    echo -e "${YELLOW}当前优选 IP/域名：$current_cfip${NC}"
    read -p "请输入新的优选 IP/域名（留空使用默认 joeyblog.net）： " input_cfip
    [ -z "$input_cfip" ] && input_cfip="joeyblog.net"
    update_config CFIP "$input_cfip"
    # 优选端口
    current_cfport=$(grep "CFPORT = " "$APP_FILE" | cut -d"'" -f2)
    echo -e "${YELLOW}当前优选端口：$current_cfport${NC}"
    read -p "请输入新的优选端口（留空保持不变）： " input_cfport
    if [ -n "$input_cfport" ]; then
        update_config CFPORT "$input_cfport"
    fi
    # Argo 端口
    current_argo=$(grep "ARGO_PORT = " "$APP_FILE" | cut -d"'" -f2)
    echo -e "${YELLOW}当前 Argo 端口：$current_argo${NC}"
    read -p "请输入新的 Argo 端口（留空保持不变）： " input_argo
    if [ -n "$input_argo" ]; then
        update_config ARGO_PORT "$input_argo"
    fi
    # 高级选项
    read -p "是否配置高级选项？(y/n): " adv_choice
    if [[ "$adv_choice" =~ ^[Yy]$ ]]; then
        current_domain=$(grep "ARGO_DOMAIN = " "$APP_FILE" | cut -d"'" -f2)
        echo -e "${YELLOW}当前 Argo 域名：$current_domain${NC}"
        read -p "请输入新的 Argo 固定隧道域名（留空保持不变）： " input_domain
        if [ -n "$input_domain" ]; then
            update_config ARGO_DOMAIN "$input_domain"
            current_auth=$(grep "ARGO_AUTH = " "$APP_FILE" | cut -d"'" -f2)
            echo -e "${YELLOW}当前 Argo 密钥：$current_auth${NC}"
            read -p "请输入新的 Argo 隧道密钥： " input_auth
            if [ -n "$input_auth" ]; then
                update_config ARGO_AUTH "$input_auth"
            fi
            echo -e "${GREEN}高级参数更新完成${NC}"
        fi
    fi
fi

# 应用 YouTube 分流及 80 端口相关补丁
patch_file="patch_yt.sh"
cat > "$patch_file" << 'EOF'
#!/bin/bash
FILE="app.py"
content=$(< "$FILE")

# 定义旧的配置块（尽量匹配多行空格，避免误匹配）
old_block="config ={[^}]*\"inbounds\":\[[^]]*\][^}]*}"
new_block="config = {
    \"log\": {
        \"access\": \"/dev/null\",
        \"error\": \"/dev/null\",
        \"loglevel\": \"none\"
    },
    \"inbounds\": [
        {
            \"port\": ARGO_PORT,
            \"protocol\": \"vless\",
            \"settings\": {
                \"clients\": [{\"id\": UUID, \"flow\": \"xtls-rprx-vision\"}],
                \"decryption\": \"none\",
                \"fallbacks\": [
                    {\"dest\": 3001},
                    {\"path\": \"/vless-argo\", \"dest\": 3002},
                    {\"path\": \"/vmess-argo\", \"dest\": 3003},
                    {\"path\": \"/trojan-argo\", \"dest\": 3004}
                ]
            },
            \"streamSettings\": {\"network\": \"tcp\"}
        },
        {
            \"port\": 3001,
            \"listen\": \"127.0.0.1\",
            \"protocol\": \"vless\",
            \"settings\": {\"clients\": [{\"id\": UUID}], \"decryption\": \"none\"},
            \"streamSettings\": {\"network\": \"ws\", \"security\": \"none\"}
        },
        {
            \"port\": 3002,
            \"listen\": \"127.0.0.1\",
            \"protocol\": \"vless\",
            \"settings\": {\"clients\": [{\"id\": UUID, \"level\": 0}], \"decryption\": \"none\"},
            \"streamSettings\": {
                \"network\": \"ws\",
                \"security\": \"none\",
                \"wsSettings\": {\"path\": \"/vless-argo\"}
            },
            \"sniffing\": {\"enabled\": true, \"destOverride\": [\"http\",\"tls\",\"quic\"], \"metadataOnly\": false}
        },
        {
            \"port\": 3003,
            \"listen\": \"127.0.0.1\",
            \"protocol\": \"vmess\",
            \"settings\": {\"clients\": [{\"id\": UUID, \"alterId\": 0}]},
            \"streamSettings\": {\"network\": \"ws\", \"wsSettings\": {\"path\": \"/vmess-argo\"}},
            \"sniffing\": {\"enabled\": true, \"destOverride\": [\"http\",\"tls\",\"quic\"], \"metadataOnly\": false}
        },
        {
            \"port\": 3004,
            \"listen\": \"127.0.0.1\",
            \"protocol\": \"trojan\",
            \"settings\": {\"clients\": [{\"password\": UUID}]},
            \"streamSettings\": {\"network\": \"ws\", \"security\": \"none\", \"wsSettings\": {\"path\": \"/trojan-argo\"}},
            \"sniffing\": {\"enabled\": true, \"destOverride\": [\"http\",\"tls\",\"quic\"], \"metadataOnly\": false}
        }
    ],
    \"outbounds\": [
        {\"protocol\": \"freedom\", \"tag\": \"direct\"},
        {
            \"protocol\": \"vmess\",
            \"tag\": \"youtube\",
            \"settings\": {
                \"vnext\": [{
                    \"address\": \"172.233.171.224\",
                    \"port\": 16416,
                    \"users\": [{\"id\": \"8c1b9bea-cb51-43bb-a65c-0af31bbbf145\", \"alterId\": 0}]
                }]
            },
            \"streamSettings\": {\"network\": \"tcp\"}
        },
        {\"protocol\": \"blackhole\", \"tag\": \"block\"}
    ],
    \"routing\": {
        \"domainStrategy\": \"IPIfNonMatch\",
        \"rules\": [
            {
                \"type\": \"field\",
                \"domain\": [
                    \"youtube.com\",
                    \"googlevideo.com\",
                    \"ytimg.com\",
                    \"gstatic.com\",
                    \"googleapis.com\",
                    \"ggpht.com\",
                    \"googleusercontent.com\"
                ],
                \"outboundTag\": \"youtube\"
            }
        ]
    }
}"
content=\$(echo "\$content" | sed -E "s/\$old_block/\$new_block/g")
echo "\$content" > "\$FILE"
echo "YouTube 分流及 80 端口配置已更新"
EOF

chmod +x "$patch_file"
./"$patch_file"
rm "$patch_file"

# 结束前先结束已运行的 Python 服务（若存在）
echo -e "${BLUE}正在终止旧的服务进程...${NC}"
pkill -f "python3 $APP_FILE" &>/dev/null
sleep 2

# 后台启动服务，并保存日志
nohup python3 "$APP_FILE" > app.log 2>&1 &
APP_PID=$!
if [ -z "$APP_PID" ] || [ "$APP_PID" -eq 0 ]; then
    sleep 2
    APP_PID=$(pgrep -f "python3 $APP_FILE" | head -1)
fi
if [ -z "$APP_PID" ]; then
    echo -e "${RED}[错误] 服务启动失败！${NC}"
    exit 1
fi
echo -e "${GREEN}服务启动成功，PID：$APP_PID${NC}"
echo -e "${YELLOW}日志存放在：$(pwd)/app.log${NC}"

# 等待节点信息生成（最多等待600秒，每5秒检查一次）
echo -e "${BLUE}等待节点信息生成中...${NC}"
MAX_WAIT=600
WAITED=0
NODE_DATA=""
while [ $WAITED -lt $MAX_WAIT ]; do
    if [ -f "$CACHE_FILE" ]; then
        NODE_DATA=$(cat "$CACHE_FILE")
    elif [ -f "$DOWNLOAD_FILE" ]; then
        NODE_DATA=$(cat "$DOWNLOAD_FILE")
    fi
    
    if [ -n "$NODE_DATA" ]; then
        echo -e "${GREEN}节点信息生成成功！${NC}"
        break
    fi
    
    if (( WAITED % 30 == 0 )); then
        echo -e "${YELLOW}等待 ${WAITED}s...${NC}"
    fi
    sleep 5
    WAITED=$((WAITED+5))
done

if [ -z "$NODE_DATA" ]; then
    echo -e "${RED}[错误] 超时未生成节点信息${NC}"
    exit 1
fi

# 显示并保存服务信息和节点信息
SERVICE_PORT=$(grep "PORT = int" "$APP_FILE" | grep -o "or [0-9]*" | cut -d" " -f2)
CURRENT_UUID=$(grep "UUID = " "$APP_FILE" | head -1 | cut -d"'" -f2)
SUB_PATH=$(grep "SUB_PATH = " "$APP_FILE" 2>/dev/null | cut -d"'" -f2)
[ -z "$SUB_PATH" ] && SUB_PATH="sub.txt" 

echo -e "${YELLOW}========== 服务信息 ==========${NC}"
echo -e "状态：${GREEN}运行中${NC}"
echo -e "PID：${BLUE}$APP_PID${NC}"
echo -e "服务端口：${BLUE}$SERVICE_PORT${NC}"
echo -e "UUID：${BLUE}$CURRENT_UUID${NC}"
echo -e "${YELLOW}============================${NC}"
echo
echo -e "${YELLOW}========== 节点信息 ==========${NC}"
DECODED=$(echo "$NODE_DATA" | base64 -d 2>/dev/null || echo "$NODE_DATA")
echo -e "${GREEN}$DECODED${NC}"
echo -e "${YELLOW}============================${NC}"
echo

# 保存节点信息到文件
PUBLIC_IP=$(curl -s https://api.ipify.org || echo "未知")
SAVE_MSG="========================================
           节点信息
========================================
部署时间: $(date)
UUID: $CURRENT_UUID
服务端口: $SERVICE_PORT
订阅路径: /$SUB_PATH

--- 访问地址 ---
订阅地址: http://$PUBLIC_IP:$SERVICE_PORT/$SUB_PATH
管理面板: http://$PUBLIC_IP:$SERVICE_PORT
本地订阅: http://localhost:$SERVICE_PORT/$SUB_PATH
本地面板: http://localhost:$SERVICE_PORT

--- 节点配置 ---
$DECODED

--- 管理命令 ---
查看日志: tail -f \$(pwd)/app.log
停止服务: kill $APP_PID
重启服务: kill $APP_PID && nohup python3 $APP_FILE > app.log 2>&1 &
查看进程: ps aux | grep python3

--- 分流说明 ---
系统已自动添加 YouTube 分流及 80 端口节点
========================================"
echo "$SAVE_MSG" > "$NODE_INFO_FILE"
echo -e "${GREEN}节点信息已保存至: $NODE_INFO_FILE${NC}"
echo -e "${GREEN}部署完成！感谢使用。${NC}"
exit 0
