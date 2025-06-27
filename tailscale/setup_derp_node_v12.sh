#!/bin/bash

# ==============================================================================
# Tailscale DERP 节点自动化部署脚本 (v12 - 2025-06-27)
#
# 特性:
# - 幂等性: 可重复安全运行，自动跳过已完成的步骤.
# - 兼容性: 自动检测并适配多种 Debian 和 Ubuntu 版本。
# - 灵活性: 支持公网信任证书和本地自签名证书两种模式。
# - 自定义: 支持自定义 derper 镜像和端口。
# - 健壮性: 遵循标准 Shell 格式，清晰、可读、无语法错误。
# ==============================================================================

set -e # 如果任何命令失败，立即退出脚本

# --- 配置变量 ---
DERP_PORT="36666" # 已按要求修改为 36666
STUN_PORT="3478"  # STUN 端口通常保持不变
CERT_DIR_NAME="certs"
DEFAULT_DOCKER_MIRROR="https://docker.1panel.live"

# 在脚本执行的目录中创建证书文件夹的绝对路径
SCRIPT_DIR=$(pwd)
CERT_DIR_PATH="${SCRIPT_DIR}/${CERT_DIR_NAME}"

# --- 辅助函数 ---
info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

warn() {
    echo -e "\033[33m[WARN]\033[0m $1"
}

error() {
    echo -e "\033[31m[ERROR]\033[0m $1" >&2
    exit 1
}

command_exists() {
    command -v "$1" &> /dev/null
}

# --- 脚本主函数 ---

# 1. 安装 Docker 和 Tailscale
install_dependencies() {
    info "--- 步骤 1: 检查并安装依赖 (Docker & Tailscale) ---"
    
    if command_exists docker && docker compose version &> /dev/null; then
        info "Docker 和 Docker Compose 已安装，跳过。"
    else
        info "正在安装 Docker 和 Docker Compose..."
        apt-get update -y
        apt-get install -y ca-certificates curl
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        systemctl enable --now docker
        info "Docker 安装完成。"
    fi

    if command_exists tailscale; then
        info "Tailscale 已安装，跳过。"
    else
        info "正在安装 Tailscale..."
        apt-get update -y
        if ! command_exists lsb_release; then
            info "正在安装 'lsb-release' 工具..."
            apt-get install -y lsb-release
        fi
        
        OS_DISTRO=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
        OS_CODENAME=$(lsb_release -cs)

        if [ "$OS_DISTRO" != "debian" ] && [ "$OS_DISTRO" != "ubuntu" ]; then
            error "不支持的操作系统: $OS_DISTRO. 此脚本仅为 Debian 和 Ubuntu 及其衍生版设计。"
        fi
        
        info "检测到当前系统为: $OS_DISTRO $OS_CODENAME"
        apt-get install -y apt-transport-https
        curl -fsSL "https://pkgs.tailscale.com/stable/${OS_DISTRO}/${OS_CODENAME}.noarmor.gpg" | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
        curl -fsSL "https://pkgs.tailscale.com/stable/${OS_DISTRO}/${OS_CODENAME}.tailscale-keyring.list" | tee /etc/apt/sources.list.d/tailscale.list
        
        TAILSCALE_LIST="/etc/apt/sources.list.d/tailscale.list"
        if ! grep -q "mirrors.ustc.edu.cn" "$TAILSCALE_LIST"; then
            info "将 Tailscale 源替换为中科大镜像..."
            sed -i 's,pkgs.tailscale.com/stable,mirrors.ustc.edu.cn/tailscale,g' "$TAILSCALE_LIST"
        fi
        
        apt-get update -y
        apt-get install -y tailscale
        info "Tailscale 安装完成。"
    fi
}

# 2. 配置 Docker 镜像源
configure_docker_mirror() {
    info "--- 步骤 2: (可选) 配置 Docker 镜像源 ---"
    read -p "您是否希望配置 Docker 镜像源以加速镜像下载? (默认: 是) [Y/n] " choice
    case "$choice" in
        [nN][oO]|[nN])
            info "跳过 Docker 镜像源配置。"
            return
            ;;
        *)
            ;;
    esac

    DAEMON_JSON_FILE="/etc/docker/daemon.json"
    MIRROR_URL="$DEFAULT_DOCKER_MIRROR"
    if [ -f "$DAEMON_JSON_FILE" ] && grep -q "$MIRROR_URL" "$DAEMON_JSON_FILE"; then
        info "Docker 镜像源已经配置为 $MIRROR_URL，跳过。"
        return
    fi

    warn "此操作将创建或覆盖 $DAEMON_JSON_FILE 文件。"
    mkdir -p /etc/docker
    tee "$DAEMON_JSON_FILE" > /dev/null <<EOF
{
  "registry-mirrors": ["$MIRROR_URL"]
}
EOF

    info "Docker 镜像源配置成功，正在重启 Docker 服务..."
    if ! systemctl restart docker; then
        error "重启 Docker 服务失败。"
    fi
    info "Docker 服务重启成功。"
}


# 3. 认证 Tailscale
authenticate_tailscale() {
    info "--- 步骤 3: 认证 Tailscale ---"
    if tailscale status &> /dev/null | grep -q "Logged in"; then
        info "Tailscale 已认证并登录，跳过。"
    else
        warn "Tailscale 尚未认证！"
        info "脚本将运行 'tailscale up'，请在浏览器中打开它生成的链接以完成认证。"
        echo
        tailscale up --accept-dns=false
        echo
        read -p "完成认证后，请按 [Enter] 键继续..."
        info "认证完成，继续执行脚本。"
    fi
}

# 4. 准备 DERP 环境和 SSL 证书
prepare_derp_environment() {
    info "--- 步骤 4: 准备 DERP 环境和 SSL 证书 ---"

    if [ -z "$DERP_DOMAIN" ]; then
        read -p "请输入您的 DERP 域名 (例如 derp.yourdomain.com): " user_domain
        if [ -z "$user_domain" ]; then error "域名不能为空。"; fi
        DERP_DOMAIN=$user_domain
    fi

    if [ ! -d "$CERT_DIR_PATH" ]; then
        info "创建证书目录: $CERT_DIR_PATH"; mkdir -p "$CERT_DIR_PATH"
    fi

    if [ -f "${CERT_DIR_PATH}/${DERP_DOMAIN}.key" ] && [ -f "${CERT_DIR_PATH}/${DERP_DOMAIN}.crt" ]; then
        info "域名 '$DERP_DOMAIN' 的 SSL 证书已存在，跳过申请步骤。"
        if openssl x509 -in "${CERT_DIR_PATH}/${DERP_DOMAIN}.crt" -noout -issuer | grep -q "Let's Encrypt"; then
             CERT_TYPE_FLAG="letsencrypt"
        else
             CERT_TYPE_FLAG="selfsigned"
        fi
        return
    fi
    
    info "请选择要使用的 SSL 证书类型:"
    read -p " [L] Let's Encrypt (公网信任，推荐) / [S] Self-signed (自签名，用于测试或无公网IP) [L/s]: " cert_choice
    case "$cert_choice" in
        [sS])
            info "您选择了 [自签名证书]。"
            CERT_TYPE_FLAG="selfsigned"
            if ! command_exists openssl; then
                info "正在安装 openssl..."; apt-get update -y && apt-get install -y openssl
            fi
            info "正在为 ${DERP_DOMAIN} 生成符合现代标准的自签名证书 (含 SANs)..."
            openssl req -x509 -newkey rsa:4096 -keyout "${CERT_DIR_PATH}/${DERP_DOMAIN}.key" \
                    -out "${CERT_DIR_PATH}/${DERP_DOMAIN}.crt" -sha256 -days 3650 -nodes \
                    -subj "/CN=${DERP_DOMAIN}" -addext "subjectAltName = DNS:${DERP_DOMAIN}"
            info "自签名证书生成完毕。"
            ;;
        *)
            info "您选择了 [Let's Encrypt] (默认)。"
            CERT_TYPE_FLAG="letsencrypt"
            ACME_CMD="$HOME/.acme.sh/acme.sh"
            if ! command_exists $ACME_CMD; then
                info "正在安装 acme.sh..."; curl https://get.acme.sh | sh; source "$HOME/.bashrc"; info "acme.sh 安装完成。"
            fi
            warn "即将为域名 $DERP_DOMAIN 申请 SSL 证书..."
            warn "=> 请确保您的域名已正确解析到本机的公网 IP。"
            warn "=> 请确保本机的 80 端口未被占用且公网可访问。"
            read -p "确认无误后，请按 [Enter] 键继续..."
            info "开始执行证书申请 (使用 ECC 证书)..."
            "$ACME_CMD" --issue -d "$DERP_DOMAIN" --standalone --keylength ec-256
            info "正在将证书安装到 $CERT_DIR_PATH..."
            "$ACME_CMD" --install-cert -d "$DERP_DOMAIN" --key-file "${CERT_DIR_PATH}/${DERP_DOMAIN}.key" \
                    --fullchain-file "${CERT_DIR_PATH}/${DERP_DOMAIN}.crt" --ecc
            info "Let's Encrypt 证书已成功部署。"
            ;;
    esac
}

# 5. 创建 docker-compose.yml 并启动服务
deploy_derper() {
    info "--- 步骤 5: 创建 docker-compose.yml 并启动 DERP 服务 ---"
    
    info "正在创建 docker-compose.yml 文件..."
    cat > "${SCRIPT_DIR}/docker-compose.yml" <<EOF
services:
  derper:
    image: javaow/tailscale-derp:latest
    container_name: derper
    restart: always
    ports:
      - "${DERP_PORT}:${DERP_PORT}"
      - "${STUN_PORT}:3478/udp"
    volumes:
      - /var/run/tailscale/tailscaled.sock:/var/run/tailscale/tailscaled.sock
      - ${CERT_DIR_PATH}:/app/certs
    environment:
      - DERP_DOMAIN=${DERP_DOMAIN}
      - DERP_ADDR=:${DERP_PORT}
      - DERP_HTTP_PORT=-1
      - DERP_CERT_MODE=manual
      - DERP_VERIFY_CLIENTS=true
      - TZ=Asia/Shanghai
      - DERP_STUN_PORT=3478
EOF

    info "docker-compose.yml 创建完成。"
    
    info "正在通过 Docker Compose 重新创建并启动 DERP 服务..."
    cd "$SCRIPT_DIR" && docker compose up -d --force-recreate
    info "DERP 服务已在后台启动。"
    docker compose ps
}

# 6. 生成最终指引
final_instructions() {
    info "--- 步骤 6: 完成！请手动更新 Tailscale ACL ---"
    
    info "您的新 DERP 节点已成功部署！"
    info "现在，请登录到您的 Tailscale 管理后台: https://login.tailscale.com/admin/acls"
    info "找到 'derpMap' 部分，并将下面生成的 JSON 代码块添加到 'Regions' 对象中。"
    warn "重要：请为您新加的节点选择一个未被使用的 RegionID (例如 911, 912...)"
    
    if [ "$CERT_TYPE_FLAG" = "selfsigned" ]; then
        warn "您使用了自签名证书，derpMap 中必须设置 \"InsecureForTests\": true"
        DERP_MAP_NODE_CONFIG=$(cat <<EOF
            {
                "Name": "derp-911",
                "RegionID": 911,
                "HostName": "${DERP_DOMAIN}",
                "DERPPort": ${DERP_PORT},
                "InsecureForTests": true
            }
EOF
)
    else
        info "您使用了公网信任证书，derpMap 中将使用默认安全设置。"
        DERP_MAP_NODE_CONFIG=$(cat <<EOF
            {
                "Name": "derp-911",
                "RegionID": 911,
                "HostName": "${DERP_DOMAIN}",
                "DERPPort": ${DERP_PORT}
            }
EOF
)
    fi

    echo
    echo -e "\033[33m>>>>>>>>>> 请复制下面的 JSON 代码块 <<<<<<<<<<\033[0m"
    echo "--------------------------------------------------"
    cat <<EOF
    "911": {
        "RegionID": 911,
        "RegionCode": "custom-node",
        "RegionName": "My New DERP Node",
        "Nodes": [
${DERP_MAP_NODE_CONFIG}
        ]
    },
EOF
    echo "--------------------------------------------------"
    echo -e "\033[33m>>>>>>>>>> 复制完毕 <<<<<<<<<<\033[0m"
    echo
    info "将其粘贴到 'Regions' 对象中，保存更改后，您的 Tailscale 网络即可使用此新中继。"
    info "部署完成！"
}


# --- 主程序执行 ---
main() {
    if [ "$(id -u)" -ne 0 ]; then
        error "此脚本需要以 root 用户权限运行。请使用 'sudo ./setup_derp_node.sh'。"
    fi
    
    install_dependencies
    configure_docker_mirror
    authenticate_tailscale
    prepare_derp_environment
    deploy_derper
    final_instructions
}

# 全局变量
DERP_DOMAIN=""
CERT_TYPE_FLAG=""
main