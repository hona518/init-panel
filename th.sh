#!/bin/bash

#############################################
#  Oracle / Debian 初始化脚本（最终稳定版）
#  作者：Amos（由 Copilot 协助优化）
#############################################

set -euo pipefail

LOG_FILE="/var/log/init.log"
STATE_DIR="/etc/init_amos"
mkdir -p "$STATE_DIR"

# 使用传统日志方式，避免 exec+tee 阻塞
exec >> "$LOG_FILE" 2>&1

# 颜色输出
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[36m"
RESET="\033[0m"

info()    { echo -e "${BLUE}[INFO]${RESET} $1"; }
success() { echo -e "${GREEN}[OK]${RESET} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $1"; }
error()   { echo -e "${RED}[ERROR]${RESET} $1"; exit 1; }

trap 'error "脚本执行中断（行号：$LINENO）"' ERR

# Root 检查
if [ "$(id -u)" -ne 0 ]; then
    error "请使用 root 运行此脚本"
fi

#############################################
# 1. Debian 版本检测
#############################################
detect_debian_version() {
    DEB_VER=$(grep -oE "[0-9]+" /etc/debian_version | head -n1)
    info "检测到 Debian 版本：$DEB_VER"
}

#############################################
# 2. 启用 BBR（幂等）
#############################################
enable_bbr() {
    if [ -f "$STATE_DIR/bbr_done" ]; then
        info "BBR 已启用，跳过"
        return
    fi

    info "启用 BBR..."
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p || true

    touch "$STATE_DIR/bbr_done"
    success "BBR 已启用"
}

#############################################
# 3. APT 源配置（幂等）
#############################################
set_apt_sources() {
    if [ -f "$STATE_DIR/sources_done" ]; then
        info "APT 源已配置，跳过"
        return
    fi

    info "配置 Debian 官方源..."
    mv /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null || true

    if [ "$DEB_VER" = "11" ]; then
        cat > /etc/apt/sources.list << EOF
deb http://deb.debian.org/debian bullseye main contrib non-free
deb http://security.debian.org/debian-security bullseye-security main contrib non-free
deb http://deb.debian.org/debian bullseye-updates main contrib non-free
deb http://archive.debian.org/debian bullseye-backports main contrib non-free
EOF
    elif [ "$DEB_VER" = "12" ]; then
        cat > /etc/apt/sources.list << EOF
deb http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ bookworm-backports main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security/ bookworm-security main contrib non-free non-free-firmware
EOF
    else
        warn "未知 Debian 版本，跳过 APT 源配置"
    fi

    touch "$STATE_DIR/sources_done"
    success "APT 源已更新"
}

#############################################
# 4. 更新系统（每次执行）
#############################################
update_system() {
    info "更新系统..."
    apt-get update || true
    apt-get upgrade -y || true
    apt-get autoremove -y || true
    apt-get autoclean -y || true
    success "系统已更新"
}

#############################################
# 5. UFW 防火墙（幂等）
#############################################
setup_ufw() {
    if [ -f "$STATE_DIR/ufw_done" ]; then
        info "UFW 已配置，跳过"
        return
    fi

    info "安装并配置 UFW..."
    apt-get install -y ufw || true
    ufw allow ssh || true
    ufw allow 52368 || true
    ufw --force enable || true
    ufw reload || true

    touch "$STATE_DIR/ufw_done"
    success "UFW 已配置"
}

#############################################
# 6. 时间同步服务（幂等）
#############################################
setup_timesync() {
    if [ -f "$STATE_DIR/timesync_done" ]; then
        info "时间同步服务已配置，跳过"
        return
    fi

    info "安装时间同步服务..."
    apt-get install -y systemd-timesyncd || true
    systemctl enable --now systemd-timesyncd || true

    touch "$STATE_DIR/timesync_done"
    success "时间同步服务已启用"
}

#############################################
# 7. 自动时区（多源 + 防中断）
#############################################
auto_timezone() {
    if [ -f "$STATE_DIR/timezone_done" ]; then
        info "时区已设置，跳过"
        return
    fi

    info "正在根据 VPS 公网 IP 自动设置时区..."

    IP=""
    for api in \
        "https://api.ipify.org" \
        "https://ifconfig.me/ip" \
        "https://ipinfo.io/ip" \
        "https://ipv4.icanhazip.com"
    do
        TMP=$(curl -s --max-time 5 "$api" || true)
        if [[ "$TMP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            IP="$TMP"
            success "获取公网 IP 成功：$IP"
            break
        fi
    done

    if [ -z "$IP" ]; then
        warn "无法获取公网 IP，跳过自动时区设置"
        return
    fi

    TZ=$(curl -s --max-time 5 "https://ipapi.co/${IP}/timezone" || true)

    if [ -n "$TZ" ] && [[ "$TZ" != "null" ]]; then
        timedatectl set-timezone "$TZ" || true
        touch "$STATE_DIR/timezone_done"
        success "系统时区已自动设置为：$TZ"
    else
        warn "无法根据 IP 获取时区，跳过自动时区设置"
    fi
}

#############################################
# 8. 自动 NTP（幂等）
#############################################
auto_ntp() {
    if [ -f "$STATE_DIR/ntp_done" ]; then
        info "NTP 已配置，跳过"
        return
    fi

    TZ=$(timedatectl | grep "Time zone" | awk '{print $3}')

    case "$TZ" in
        Asia/*)                 NTP_SERVER="asia.pool.ntp.org" ;;
        Europe/*)               NTP_SERVER="europe.pool.ntp.org" ;;
        America/*)              NTP_SERVER="north-america.pool.ntp.org" ;;
        Africa/*)               NTP_SERVER="africa.pool.ntp.org" ;;
        Oceania/*|Australia/*)  NTP_SERVER="oceania.pool.ntp.org" ;;
        *)                      NTP_SERVER="pool.ntp.org" ;;
    esac

    cat > /etc/systemd/timesyncd.conf << EOF
[Time]
NTP=$NTP_SERVER
FallbackNTP=pool.ntp.org
EOF

    systemctl restart systemd-timesyncd || true

    touch "$STATE_DIR/ntp_done"
    success "NTP 已自动配置为：$NTP_SERVER"
}

#############################################
# 9. NTP 健康检查
#############################################
check_ntp_status() {
    info "正在检查 NTP 同步状态..."

    STATUS=$(timedatectl status || true)
    echo "$STATUS"

    SYNCED=$(echo "$STATUS" | grep "System clock synchronized" | awk '{print $4}')

    if [ "$SYNCED" = "yes" ]; then
        success "NTP 同步正常"
    else
        warn "NTP 同步异常，尝试修复..."
        systemctl restart systemd-timesyncd || true
    fi
}

#############################################
# 10. Fail2ban（幂等）
#############################################
setup_fail2ban() {
    if [ -f "$STATE_DIR/fail2ban_done" ]; then
        info "Fail2ban 已配置，跳过"
        return
    fi

    info "安装 Fail2ban..."
    apt-get install -y fail2ban || true

    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
findtime = 600
maxretry = 3
backend  = systemd
ignoreip = 127.0.0.1/8 ::1
bantime = 86400
bantime.increment = true
bantime.factor = 7
bantime.maxtime = -1

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
EOF

    systemctl restart fail2ban || true

    touch "$STATE_DIR/fail2ban_done"
    success "Fail2ban 已配置"
}

#############################################
# 11. 写入 sing-box 默认配置（仅首次安装/修复）
#############################################
write_singbox_config() {
cat > /etc/sing-box/config.json << 'EOF'
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    {
      "type": "vless",
      "tag": "VLESSReality",
      "listen": "0.0.0.0",
      "listen_port": 52368,
      "users": [
        {
          "name": "xwbay-VLESS_Reality_Vision",
          "uuid": "0a733f17-af5c-46e6-a7fd-021677069d6f",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.amd.com",
        "reality": {
          "enabled": true,
          "handshake": { "server": "www.amd.com", "server_port": 443 },
          "private_key": "OGYviki2votqKBOpVODriLzCZhgkl6xq0Mw-w2UAFFk",
          "short_id": ["6ba85179e30d4fc2"]
        }
      }
    }
  ]
}
EOF
}

#############################################
# 12. sing-box 安装 / 更新 / 修复
#############################################
install_singbox() {
    info "检查 sing-box 状态..."

    mkdir -p /etc/sing-box

    set +e

    if command -v sing-box >/dev/null 2>&1; then
        CURRENT_VER=$(sing-box version 2>/dev/null | head -n1 | awk '{print $3}')
        CUR_RC=0
    else
        CURRENT_VER=""
        CUR_RC=1
    fi

    LATEST_VER=$(curl -s --max-time 5 https://api.github.com/repos/SagerNet/sing-box/releases/latest \
        | grep tag_name | cut -d '"' -f4 | sed 's/^v//' )

    if [ $CUR_RC -ne 0 ] || [ -z "$CURRENT_VER" ]; then
        info "未检测到 sing-box，正在首次安装..."
        curl -fsSL --max-time 10 https://sing-box.app/install.sh | sh
        INST_RC=$?

        if [ $INST_RC -ne 0 ]; then
            warn "sing-box 安装失败（首次），跳过配置与启动"
            set -e
            return
        fi

        write_singbox_config
        systemctl enable sing-box >/dev/null 2>&1
        systemctl restart sing-box >/dev/null 2>&1

        if systemctl is-active --quiet sing-box; then
            success "sing-box 首次安装并成功启动"
        else
            warn "sing-box 首次安装后启动失败，请检查 /etc/sing-box/config.json"
        fi

        set -e
        return
    fi

    info "当前 sing-box 版本：$CURRENT_VER"

    if [ -n "$LATEST_VER" ] && [ "$CURRENT_VER" != "$LATEST_VER" ]; then
        printf "检测到 sing-box 有更新（$CURRENT_VER → $LATEST_VER），是否更新？(y/n): "
        read choice

        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            curl -fsSL --max-time 10 https://sing-box.app/install.sh | sh
            if [ $? -ne 0 ]; then
                warn "sing-box 更新失败，保留当前版本：$CURRENT_VER"
            else
                success "sing-box 已更新到最新版本：$LATEST_VER"
            fi
        else
            info "已跳过 sing-box 更新"
        fi
    fi

    systemctl is-active --quiet sing-box
    SVC_RC=$?

    if [ $SVC_RC -ne 0 ]; then
        warn "检测到 sing-box 服务未正常运行，尝试自动修复..."

        curl -fsSL --max-time 10 https://sing-box.app/install.sh | sh
        if [ $? -ne 0 ]; then
            warn "sing-box 自动修复失败，跳过后续操作"
            set -e
            return
        fi

        write_singbox_config

        systemctl restart sing-box >/dev/null 2>&1

        if systemctl is-active --quiet sing-box; then
            success "sing-box 服务修复完成并成功启动"
        else
            warn "sing-box 修复后仍无法启动，请检查配置与日志"
        fi
    else
        success "sing-box 服务运行正常，不覆盖现有配置"
    fi

    set -e
}

#############################################
# 13. 自动检测 Oracle Cloud（ASN = 31898）
#############################################
is_oracle_cloud() {
    IP=$(curl -s --max-time 5 https://api.ipify.org || true)

    if [[ ! "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 1
    fi

    ASN=$(curl -s --max-time 5 https://ipinfo.io/$IP/org 2>/dev/null \
        | awk '{print $1}' | sed 's/AS//' || true)

    if [ -z "$ASN" ]; then
        ASN=$(curl -s --max-time 5 https://ipapi.co/$IP/asn 2>/dev/null \
            | sed 's/AS//' || true)
    fi

    [ "$ASN" = "31898" ]
}

#############################################
# 14. Oracle Cloud 专属优化
#############################################
oracle_optimizations() {

    if ! is_oracle_cloud; then
        info "非 Oracle Cloud 环境，跳过 Oracle 优化"
        return
    fi

    if [ -f "$STATE_DIR/oracle_opt_done" ]; then
        info "Oracle 优化已执行过，跳过"
        return
    fi

    echo
    warn "检测到 Oracle Cloud 环境，可用的专属优化如下："
    echo -e "  1) 网卡队列优化（ethtool）"
    echo -e "  2) CPU governor 切换 performance"
    echo -e "  3) 网卡 offload/GRO/GSO/TSO 优化"
    echo -e "  4) sysctl 网络优化"
    echo

    printf "是否执行这些优化？(y/n): "
    read choice

    if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
        warn "已跳过 Oracle Cloud 专属优化"
        return
    fi

    REPORT="/var/log/oracle_optimization_report.txt"
    echo "Oracle Cloud 优化报告" > "$REPORT"
    echo "执行时间：$(date)" >> "$REPORT"
    echo "----------------------------------------" >> "$REPORT"

    NIC=$(ls /sys/class/net | grep -E "ens|eth|enp|eno" | head -n1 2>/dev/null || true)

    if [ -z "$NIC" ]; then
        warn "未找到可用网卡，跳过网卡优化"
        echo "[WARN] 未找到可用网卡" >> "$REPORT"
    else
        if command -v ethtool >/dev/null 2>&1; then
            ethtool -G "$NIC" rx 4096 tx 4096 || true
            ethtool -K "$NIC" gro on gso on tso on || true
            echo "[OK] 网卡优化已应用（$NIC）" >> "$REPORT"
            success "网卡优化完成（$NIC）"
        else
            warn "ethtool 未安装，跳过网卡优化"
            echo "[WARN] ethtool 未安装" >> "$REPORT"
        fi
    fi

    apt-get install -y cpufrequtils || true
    cpufreq-set -g performance || true
    echo "[OK] CPU governor 已切换为 performance" >> "$REPORT"
    success "CPU governor 已切换为 performance"

    if ! grep -q "Oracle Cloud 网络优化" /etc/sysctl.conf 2>/dev/null; then
        cat >> /etc/sysctl.conf << EOF

# Oracle Cloud 网络优化
net.core.rmem_max = 2500000
net.core.wmem_max = 2500000
net.ipv4.tcp_rmem = 4096 87380 2500000
net.ipv4.tcp_wmem = 4096 65536 2500000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
EOF
    fi

    sysctl -p || true
    echo "[OK] sysctl 网络优化已应用" >> "$REPORT"
    success "sysctl 网络优化已应用"

    echo "----------------------------------------" >> "$REPORT"
    echo "优化已全部完成" >> "$REPORT"

    touch "$STATE_DIR/oracle_opt_done"
    success "Oracle Cloud 专属优化全部完成"
    info "优化报告已生成：$REPORT"

    echo
    printf "是否在优化完成后自动重启系统？(y/n): "
    read reboot_choice

    if [[ "$reboot_choice" == "y" || "$reboot_choice" == "Y" ]]; then
        success "系统将在 3 秒后自动重启..."
        sleep 3
        reboot
    else
        warn "已跳过自动重启"
    fi
}

#############################################
# 15. 主流程
#############################################
main() {
    info "===== init.sh 开始执行 ====="
    detect_debian_version
    enable_bbr
    set_apt_sources
    update_system
    setup_ufw
    setup_timesync
    auto_timezone
    auto_ntp
    check_ntp_status
    setup_fail2ban
    install_singbox
    oracle_optimizations

    success "全部任务执行完毕！系统已成功初始化"
    info "日志文件：$LOG_FILE"
}

main
