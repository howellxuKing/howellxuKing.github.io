#!/usr/bin/env bash
# ==============================================================================
# Project: XWarp AI 极速一键部署脚本 (Hysteria 2 混淆版)
# Author: howellxuKing
# Description: 纯 IP + 自签名证书 + Salamander 混淆 + 自动输出客户端 KEY
# ==============================================================================

set -e

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
BOLD="\033[1m"
RESET="\033[0m"

echo -e "${CYAN}${BOLD}"
echo "=========================================================="
echo "          XWarp AI 专线服务端一键部署程序                "
echo "        (Hysteria 2 高速协议 + 纯IP免域名自签名)         "
echo "=========================================================="
echo -e "${RESET}"

# 1. 检查 root 权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[错误] 请以 root 权限运行此脚本 (例如: sudo bash install.sh)${RESET}"
   exit 1
fi

# 2. 自动探测公网 IPv4
echo -e "${YELLOW}[1/6] 正在获取公网 IPv4 地址...${RESET}"
SERVER_IP=$(curl -4s --connect-timeout 5 https://api.ipify.org || curl -4s --connect-timeout 5 https://ifconfig.me || curl -4s --connect-timeout 5 https://icanhazip.com)
if [[ -z "$SERVER_IP" ]]; then
    read -r -p "未能自动获取到公网 IP，请输入本服务器公网 IP: " SERVER_IP
fi
echo -e "${GREEN}✓ 服务器 IP: ${SERVER_IP}${RESET}"

# 3. 安装必备依赖 (curl, openssl, iptables)
echo -e "${YELLOW}[2/6] 检查系统基础依赖...${RESET}"
if command -v apt-get &>/dev/null; then
    apt-get update -y && apt-get install -y curl openssl iptables
elif command -v yum &>/dev/null; then
    yum install -y curl openssl iptables
fi

# 4. 下载并安装官方原生 Hysteria 2 二进制核心
echo -e "${YELLOW}[3/6] 安装 Hysteria 2 原生协议核心...${RESET}"
mkdir -p /etc/xwarp /usr/local/bin

ARCH=$(uname -m)
case "$ARCH" in
    x86_64) HY2_ARCH="amd64" ;;
    aarch64|arm64) HY2_ARCH="arm64" ;;
    *) echo -e "${RED}[错误] 不支持的 CPU 架构: $ARCH${RESET}"; exit 1 ;;
esac

HY2_VER=$(curl -s "https://api.github.com/repos/apernet/hysteria/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
if [[ -z "$HY2_VER" ]]; then
    HY2_VER="app/v2.5.1"
fi
echo -e "${GREEN}✓ 核心版本: ${HY2_VER} (${HY2_ARCH})${RESET}"

curl -Lo /usr/local/bin/xwarp-core "https://github.com/apernet/hysteria/releases/download/${HY2_VER}/hysteria-linux-${HY2_ARCH}"
chmod +x /usr/local/bin/xwarp-core

# 5. 生成 100 年免维护自签名证书 (伪装成 gateway.icloud.com)
echo -e "${YELLOW}[4/6] 生成本地自签名加密证书...${RESET}"
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
  -keyout /etc/xwarp/server.key \
  -out /etc/xwarp/server.crt \
  -days 36500 \
  -subj "/CN=gateway.icloud.com" &>/dev/null
echo -e "${GREEN}✓ 自签名证书生成完毕 (有效期 100 年)${RESET}"

# 6. 生成高强度密码与端口
LISTEN_PORT=3443
AUTH_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
OBFS_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)

# 7. 写入 AI 白名单 ACL 规则 (防止被滥用于其他流量)
cat > /etc/xwarp/ai_whitelist.acl << 'EOF'
# ==================== XWarp AI 专属白名单 ====================
# 允许主流国外 AI 域名
direct(domain-suffix:openai.com)
direct(domain-suffix:chatgpt.com)
direct(domain-suffix:oaistatic.com)
direct(domain-suffix:oaiusercontent.com)
direct(domain-suffix:anthropic.com)
direct(domain-suffix:claude.ai)
direct(domain-suffix:meta.ai)
direct(domain-suffix:perplexity.ai)
direct(domain-suffix:deepseek.com)
direct(domain-suffix:groq.com)
direct(domain-suffix:midjourney.com)
direct(domain-suffix:suno.com)
direct(domain-suffix:suno.ai)
direct(domain-suffix:cohere.com)
direct(domain-suffix:mistral.ai)
direct(domain-suffix:x.ai)
direct(domain-suffix:grok.com)
direct(domain-suffix:huggingface.co)
direct(domain-suffix:cursor.com)
direct(domain-suffix:cursor.sh)
# 其余非 AI 流量全部阻断 (杜绝违规风险)
reject(all)
EOF

# 8. 写入 Hysteria 2 配置文件
echo -e "${YELLOW}[5/6] 写入服务运行配置...${RESET}"
cat > /etc/xwarp/config.yaml << EOF
listen: :${LISTEN_PORT}

tls:
  cert: /etc/xwarp/server.crt
  key: /etc/xwarp/server.key

obfs:
  type: salamander
  salamander:
    password: ${OBFS_PASS}

auth:
  type: password
  password: ${AUTH_PASS}

acl:
  file: /etc/xwarp/ai_whitelist.acl

masquerade:
  type: proxy
  proxy:
    url: https://gateway.icloud.com
    rewriteHost: true

bandwidth:
  up: 100 mbps
  down: 500 mbps
EOF

# 9. 注册系统 Systemd 开机自启服务
cat > /etc/systemd/system/xwarp-hy2.service << 'EOF'
[Unit]
Description=XWarp Hysteria2 Server Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xwarp-core server --config /etc/xwarp/config.yaml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xwarp-hy2 &>/dev/null
systemctl restart xwarp-hy2

# 10. 放行防火墙端口 (UDP)
if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
    ufw allow ${LISTEN_PORT}/udp &>/dev/null
elif command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
    firewall-cmd --add-port=${LISTEN_PORT}/udp --permanent &>/dev/null
    firewall-cmd --reload &>/dev/null
fi

# 11. 生成客户端专用标准连接和 XWARP-KEY
RAW_URI="hy2://${AUTH_PASS}@${SERVER_IP}:${LISTEN_PORT}/?insecure=1&sni=gateway.icloud.com&obfs=salamander&obfs-password=${OBFS_PASS}#XWarp-AI"
XWARP_KEY="XWARP://$(echo -n "$RAW_URI" | base64 -w 0)"

# 12. 保存配置备份到本地
cat > /etc/xwarp/client_info.txt << EOF
==================== XWarp 客户节点信息 ====================
服务器 IP: ${SERVER_IP}
服务端口: ${LISTEN_PORT} (UDP)
认证密码: ${AUTH_PASS}
混淆密码: ${OBFS_PASS}
SNI 伪装: gateway.icloud.com
跳过证书: insecure=1 (自签名模式)

原生 URI 链接:
${RAW_URI}

XWarp 专属激活 KEY:
${XWARP_KEY}
============================================================
EOF

# 13. 打印精美发货卡片
echo ""
echo -e "${GREEN}${BOLD}==============================================================${RESET}"
echo -e "${GREEN}${BOLD}           🎉 XWarp AI 专线服务器部署成功！                  ${RESET}"
echo -e "${GREEN}${BOLD}==============================================================${RESET}"
echo -e " 协议模式: ${CYAN}Hysteria 2 (UDP 高速混淆 + 纯IP自签名)${RESET}"
echo -e " 分流策略: ${CYAN}仅限国外主流 AI (ChatGPT / Claude 等)，其余全拦截${RESET}"
echo -e " 节点备份: ${CYAN}/etc/xwarp/client_info.txt${RESET}"
echo ""
echo -e "${BOLD}------------------ 【直接发给客户的激活码】 ------------------${RESET}"
echo -e "${YELLOW}${BOLD}${XWARP_KEY}${RESET}"
echo -e "${BOLD}--------------------------------------------------------------${RESET}"
echo ""
echo -e "通用原生链接 (导入 Clash / v2rayN 等备用):"
echo -e "${CYAN}${RAW_URI}${RESET}"
echo -e "${GREEN}==============================================================${RESET}"
echo ""
