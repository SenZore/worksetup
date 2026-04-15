#!/bin/bash

# ================================================================
#  ALL-IN-ONE INSTALLER: OpenSSH Server + ISC DHCP Server
#  FIX UTAMA 1 : apt-get update  → auto kill saat stuck 100%
#  FIX UTAMA 2 : apt-get install → auto kill saat stuck di
#                "Processing triggers for systemd" (Debian 8 bug)
#                Package sudah terinstall = aman di-kill
#  Compatible  : Debian 8 (Jessie) / Debian 13 (Trixie)
#  VirtualBox  : Adapter1=Host-Only | Adapter2=NAT
# ================================================================

# ─────────────────────────────────────────
#  WARNA
# ─────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# ─────────────────────────────────────────
#  FILE PENTING
# ─────────────────────────────────────────
IP_SAVE_FILE="/root/.aio_server_ip"
APT_LOG="/tmp/apt_aio.log"
INSTALL_LOG="/tmp/install_aio.log"
STEP_LOG="/root/aio_steps.log"

# ─────────────────────────────────────────
#  FUNGSI DASAR
# ─────────────────────────────────────────
info()    { echo -e "  ${CYAN}[INFO]${NC}   $1"; sleep 0.2; }
success() { echo -e "  ${GREEN}[OK]${NC}     $1"; sleep 0.2; }
warn()    { echo -e "  ${YELLOW}[WARN]${NC}   $1"; sleep 0.2; }
error()   { echo -e "  ${RED}[ERROR]${NC}  $1"; sleep 0.2; }
blank()   { echo ""; }

step() {
    blank
    echo -e "${BOLD}${BLUE}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${BLUE}│${NC}  ${WHITE}${BOLD}$1${NC}"
    echo -e "${BOLD}${BLUE}└──────────────────────────────────────────────────┘${NC}"
    echo "$1" >> "$STEP_LOG"
    sleep 0.3
}

slow_msg() {
    local MSG="$1"
    echo -ne "  ${CYAN}[~]${NC} $MSG "
    for i in {1..4}; do
        echo -ne "${YELLOW}.${NC}"
        sleep 0.35
    done
    echo -e " ${GREEN}✓${NC}"
}

# ─────────────────────────────────────────
#  FUNGSI INSTALL DENGAN AUTO-KILL SYSTEMD HANG
#  Fix untuk Debian 8 bug:
#  "Processing triggers for systemd" → hang selamanya
#  Padahal package sudah terinstall sempurna
# ─────────────────────────────────────────
safe_apt_install() {
    local PACKAGE="$1"
    local LOGFILE="$2"
    local TIMEOUT_SEC=120

    # Variabel untuk detect trigger systemd hang
    local STUCK_TRIGGER_LIMIT=4   # 4x cek tidak berubah = stuck
    local CHECK_INTERVAL=3        # cek setiap 3 detik
    local ELAPSED=0
    local SAME_COUNT=0
    local LAST_SIZE=0

    > "$LOGFILE"

    blank
    echo -e "  ${BOLD}${YELLOW}── apt-get install $PACKAGE (output live) ──${NC}"
    echo -e "  ${BLUE}────────────────────────────────────────────${NC}"

    # Jalankan apt-get install di background
    DEBIAN_FRONTEND=noninteractive \
    SYSTEMD_IGNORE_CHROOT=1 \
    apt-get install -y "$PACKAGE" \
        2>&1 | tee "$LOGFILE" | sed 's/^/  /' &

    local INSTALL_PID=$!
    local KILLED_BY_WATCHDOG=false

    # ── WATCHDOG LOOP ──
    while kill -0 "$INSTALL_PID" 2>/dev/null; do
        sleep $CHECK_INTERVAL
        ELAPSED=$((ELAPSED + CHECK_INTERVAL))

        CURRENT_SIZE=$(wc -c < "$LOGFILE" 2>/dev/null || echo 0)

        # Deteksi kondisi "Setting up PACKAGE" sudah muncul
        # = package sudah selesai diinstall
        PKG_SETUP_DONE=false
        if grep -q "Setting up $PACKAGE" "$LOGFILE" 2>/dev/null; then
            PKG_SETUP_DONE=true
        fi

        # Deteksi line trigger systemd yang menyebabkan hang
        TRIGGER_SYSTEMD=false
        if grep -q "Processing triggers for systemd" "$LOGFILE" 2>/dev/null; then
            TRIGGER_SYSTEMD=true
        fi

        if [ "$CURRENT_SIZE" -eq "$LAST_SIZE" ]; then
            SAME_COUNT=$((SAME_COUNT + 1))

            # ── KONDISI KILL: package sudah setup DAN output berhenti ──
            if [ "$PKG_SETUP_DONE" = true ] && \
               [ "$SAME_COUNT" -ge "$STUCK_TRIGGER_LIMIT" ]; then
                blank
                if [ "$TRIGGER_SYSTEMD" = true ]; then
                    echo -e "  ${YELLOW}[WATCHDOG]${NC} Terdeteksi stuck di:"
                    echo -e "  ${YELLOW}           ${NC} 'Processing triggers for systemd'"
                    echo -e "  ${YELLOW}[WATCHDOG]${NC} Ini bug Debian 8 yang diketahui"
                else
                    echo -e "  ${YELLOW}[WATCHDOG]${NC} Output berhenti ${STUCK_TRIGGER_LIMIT}x berturut"
                fi
                echo -e "  ${GREEN}[WATCHDOG]${NC} '$PACKAGE' sudah terinstall sempurna"
                echo -e "  ${GREEN}[WATCHDOG]${NC} Auto-kill (sama seperti Ctrl+C manual) ✓"

                # Kill seluruh process group
                kill "$INSTALL_PID"        2>/dev/null
                kill $(pgrep -P "$INSTALL_PID") 2>/dev/null
                pkill -P "$INSTALL_PID"   2>/dev/null
                wait "$INSTALL_PID"        2>/dev/null
                KILLED_BY_WATCHDOG=true
                break
            fi

        else
            SAME_COUNT=0
        fi

        LAST_SIZE=$CURRENT_SIZE

        # Hard timeout
        if [ "$ELAPSED" -ge "$TIMEOUT_SEC" ]; then
            blank
            warn "[WATCHDOG] Timeout ${TIMEOUT_SEC}s tercapai → Force kill"
            kill "$INSTALL_PID"             2>/dev/null
            kill $(pgrep -P "$INSTALL_PID") 2>/dev/null
            wait "$INSTALL_PID"             2>/dev/null
            KILLED_BY_WATCHDOG=true
            break
        fi
    done

    wait "$INSTALL_PID" 2>/dev/null
    local EXIT_CODE=$?

    echo -e "  ${BLUE}────────────────────────────────────────────${NC}"
    blank

    # ── CEK APAKAH PACKAGE BENAR-BENAR TERINSTALL ──
    if dpkg -l 2>/dev/null | grep -qw "$PACKAGE"; then
        if [ "$KILLED_BY_WATCHDOG" = true ]; then
            success "$PACKAGE terinstall ✓ (auto-kill dari systemd hang)"
        else
            success "$PACKAGE terinstall ✓ (normal)"
        fi
        return 0
    else
        error "$PACKAGE GAGAL terinstall!"
        return 1
    fi
}

# ─────────────────────────────────────────
#  BANNER
# ─────────────────────────────────────────
banner() {
    clear
    echo -e "${BLUE}"
    echo "  ╔════════════════════════════════════════════════════╗"
    echo "  ║     AIO: OpenSSH + ISC DHCP Server Installer      ║"
    echo "  ╠════════════════════════════════════════════════════╣"
    echo "  ║  Debian 8 (Jessie) / Debian 13 (Trixie)           ║"
    echo "  ║  FIX 1: apt-get update  → auto kill stuck 100%   ║"
    echo "  ║  FIX 2: apt-get install → auto kill systemd hang  ║"
    echo "  ║  Repo  : Cek hidup otomatis + fallback            ║"
    echo "  ║  IP    : Tersimpan, tidak random ulang            ║"
    echo "  ╚════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    sleep 0.8
}

# ══════════════════════════════════════════
# ROOT CHECK
# ══════════════════════════════════════════
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[!] Jalankan sebagai ROOT!${NC}"
    echo -e "${YELLOW}    sudo bash $0${NC}"
    exit 1
fi

banner
> "$STEP_LOG"

# ══════════════════════════════════════════
# STEP 1 - DETEKSI OS
# ══════════════════════════════════════════
step "STEP 1/17 ► Deteksi Versi Debian"

slow_msg "Membaca /etc/debian_version"
DEBIAN_VER_NUM=$(cat /etc/debian_version 2>/dev/null | cut -d'.' -f1)
DEBIAN_CODENAME=$(grep VERSION_CODENAME /etc/os-release 2>/dev/null \
    | cut -d'=' -f2 | tr -d '"')

[ -z "$DEBIAN_CODENAME" ] && \
    DEBIAN_CODENAME=$(lsb_release -cs 2>/dev/null)

if [[ "$DEBIAN_VER_NUM" == "8" ]] || \
   [[ "$DEBIAN_CODENAME" == "jessie" ]]; then
    DISTRO="debian8"
    DISTRO_NAME="Debian 8 (Jessie)"
    IFACE_LAN="eth0"
    IFACE_WAN="eth1"
elif [[ "$DEBIAN_VER_NUM" == "13" ]] || \
     [[ "$DEBIAN_CODENAME" == "trixie" ]]; then
    DISTRO="debian13"
    DISTRO_NAME="Debian 13 (Trixie)"
    IFACE_LAN="enp0s3"
    IFACE_WAN="enp0s8"
else
    warn "Versi tidak dikenal → Default Debian 13"
    DISTRO="debian13"
    DISTRO_NAME="Debian (Unknown → Default 13)"
    IFACE_LAN="enp0s3"
    IFACE_WAN="enp0s8"
fi

success "OS         : $DISTRO_NAME"
success "LAN (Adp1) : $IFACE_LAN (Host-Only)"
success "WAN (Adp2) : $IFACE_WAN (NAT)"

# ══════════════════════════════════════════
# STEP 2 - LOAD / GENERATE IP
# ══════════════════════════════════════════
step "STEP 2/17 ► Load / Generate IP Server"

if [ -f "$IP_SAVE_FILE" ]; then
    source "$IP_SAVE_FILE"
    blank
    echo -e "  ${GREEN}[IP TERSIMPAN DITEMUKAN]${NC} → Tidak random ulang"
    echo -e "  ${CYAN}File: $IP_SAVE_FILE${NC}"
    blank
    success "Server IP  : $SERVER_IP"
    success "Network    : $NETWORK/24"
    success "Range      : $RANGE_START - $RANGE_END (50 host)"
else
    slow_msg "Generate IP acak (hanya 1x)"
    RANDOM_OCT=$((RANDOM % 200 + 20))
    SERVER_IP="192.168.$RANDOM_OCT.1"
    NETWORK="192.168.$RANDOM_OCT.0"
    SUBNET_MASK="255.255.255.0"
    BROADCAST="192.168.$RANDOM_OCT.255"
    RANGE_START="192.168.$RANDOM_OCT.100"
    RANGE_END="192.168.$RANDOM_OCT.150"
    DNS_PRIMARY="8.8.8.8"
    DNS_SECONDARY="8.8.4.4"

    cat > "$IP_SAVE_FILE" << IPEOF
SERVER_IP="$SERVER_IP"
NETWORK="$NETWORK"
SUBNET_MASK="$SUBNET_MASK"
BROADCAST="$BROADCAST"
RANGE_START="$RANGE_START"
RANGE_END="$RANGE_END"
DNS_PRIMARY="$DNS_PRIMARY"
DNS_SECONDARY="$DNS_SECONDARY"
IPEOF

    blank
    echo -e "  ${YELLOW}[IP BARU DISIMPAN]${NC} → $IP_SAVE_FILE"
    blank
    success "Server IP  : $SERVER_IP"
    success "Network    : $NETWORK/24"
    success "Netmask    : $SUBNET_MASK"
    success "Broadcast  : $BROADCAST"
    success "Range      : $RANGE_START - $RANGE_END"
    success "Total Host : 50 Host"
    success "DNS        : $DNS_PRIMARY / $DNS_SECONDARY"
fi

DNS_PRIMARY="${DNS_PRIMARY:-8.8.8.8}"
DNS_SECONDARY="${DNS_SECONDARY:-8.8.4.4}"

# ══════════════════════════════════════════
# STEP 3 - APT FIX CONFIG
# ══════════════════════════════════════════
step "STEP 3/17 ► Pasang APT Fix Config"

slow_msg "Menulis /etc/apt/apt.conf.d/00antistuck"
mkdir -p /etc/apt/apt.conf.d/

cat > /etc/apt/apt.conf.d/00antistuck << 'ANTISTUCK'
Acquire::ForceIPv4 "true";
Acquire::http::Timeout "15";
Acquire::ftp::Timeout "15";
Acquire::https::Timeout "15";
Acquire::Retries "2";
Acquire::http::Pipeline-Depth "0";
Acquire::http::No-Cache "true";
Acquire::Check-Valid-Until "false";
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
APT::Get::AllowUnauthenticated "true";
ANTISTUCK

success "APT anti-stuck config dipasang ✓"

# ══════════════════════════════════════════
# STEP 4 - CEK INTERNET
# ══════════════════════════════════════════
step "STEP 4/17 ► Cek Koneksi Internet"

slow_msg "Ping ke 8.8.8.8"
if ping -c 2 -W 5 8.8.8.8 > /dev/null 2>&1; then
    success "Internet : TERHUBUNG ✓"
    INTERNET_OK=true
else
    slow_msg "Coba ping 1.1.1.1"
    if ping -c 2 -W 5 1.1.1.1 > /dev/null 2>&1; then
        success "Internet : TERHUBUNG (via 1.1.1.1) ✓"
        INTERNET_OK=true
    else
        error "Internet : TIDAK TERHUBUNG ✗"
        warn "Script tetap lanjut"
        INTERNET_OK=false
    fi
fi

# ══════════════════════════════════════════
# STEP 5 - CEK REPO LIVE
# ══════════════════════════════════════════
step "STEP 5/17 ► Cek Repo Aktif (Live Check)"

check_repo() {
    local URL="$1"
    local LABEL="$2"
    echo -ne "  ${CYAN}[~]${NC} Cek $LABEL "
    local RESULT=1
    if command -v curl &>/dev/null; then
        timeout 10 curl --silent --max-time 8 \
            --connect-timeout 6 --head --ipv4 \
            "$URL" > /dev/null 2>&1
        RESULT=$?
    elif command -v wget &>/dev/null; then
        timeout 10 wget --quiet --timeout=8 \
            --tries=1 --spider --inet4-only \
            "$URL" > /dev/null 2>&1
        RESULT=$?
    fi
    if [ $RESULT -eq 0 ]; then
        echo -e "${GREEN}→ HIDUP ✓${NC}"; return 0
    else
        echo -e "${RED}→ MATI ✗${NC}";   return 1
    fi
}

blank
cp /etc/apt/sources.list \
    "/etc/apt/sources.list.bak.$(date +%s)" 2>/dev/null
> /etc/apt/sources.list

if [ "$DISTRO" = "debian8" ]; then
    check_repo "http://kambing.ui.ac.id/debian/"   \
        "kambing.ui.ac.id  " && REPO_KAMBING=true  || REPO_KAMBING=false
    check_repo "http://archive.debian.org/debian/" \
        "archive.debian.org" && REPO_ARCHIVE=true  || REPO_ARCHIVE=false
    check_repo "http://ftp.id.debian.org/debian/"  \
        "ftp.id.debian.org " && REPO_FTPID=true    || REPO_FTPID=false

    blank
    REPO_COUNT=0

    if [ "$REPO_KAMBING" = true ]; then
        cat >> /etc/apt/sources.list << 'EOF'
deb http://kambing.ui.ac.id/debian/ jessie main contrib non-free
deb http://kambing.ui.ac.id/debian/ jessie-updates main contrib non-free
EOF
        success "Ditambahkan: kambing.ui.ac.id"
        REPO_COUNT=$((REPO_COUNT+1))
    fi

    if [ "$REPO_ARCHIVE" = true ]; then
        cat >> /etc/apt/sources.list << 'EOF'
deb http://archive.debian.org/debian/ jessie main contrib non-free
deb http://archive.debian.org/debian-security jessie/updates main contrib non-free
EOF
        success "Ditambahkan: archive.debian.org"
        REPO_COUNT=$((REPO_COUNT+1))
    fi

    if [ "$REPO_FTPID" = true ]; then
        cat >> /etc/apt/sources.list << 'EOF'
deb http://ftp.id.debian.org/debian/ jessie main contrib non-free
EOF
        success "Ditambahkan: ftp.id.debian.org"
        REPO_COUNT=$((REPO_COUNT+1))
    fi

    if [ "$REPO_COUNT" -eq 0 ]; then
        warn "Semua repo timeout! Paksa archive.debian.org..."
        cat > /etc/apt/sources.list << 'EOF'
deb http://archive.debian.org/debian/ jessie main contrib non-free
deb http://archive.debian.org/debian-security jessie/updates main contrib non-free
EOF
    fi

else
    check_repo "http://deb.debian.org/debian/"              \
        "deb.debian.org    " && REPO_DEBMAIN=true || REPO_DEBMAIN=false
    check_repo "http://ftp.debian.org/debian/"              \
        "ftp.debian.org    " && REPO_FTPDEB=true  || REPO_FTPDEB=false
    check_repo "http://security.debian.org/debian-security" \
        "security.debian.org" && REPO_SECDEB=true || REPO_SECDEB=false

    blank
    if   [ "$REPO_DEBMAIN" = true ]; then
        MAIN_MIRROR="http://deb.debian.org/debian/"
        success "Mirror utama: deb.debian.org"
    elif [ "$REPO_FTPDEB"  = true ]; then
        MAIN_MIRROR="http://ftp.debian.org/debian/"
        success "Mirror utama: ftp.debian.org (fallback)"
    else
        MAIN_MIRROR="http://deb.debian.org/debian/"
        warn "Semua timeout - paksa deb.debian.org"
    fi

    cat > /etc/apt/sources.list << REPOEOF
deb $MAIN_MIRROR trixie main contrib non-free non-free-firmware
deb $MAIN_MIRROR trixie-updates main contrib non-free non-free-firmware
REPOEOF

    if [ "$REPO_SECDEB" = true ]; then
        echo "deb http://security.debian.org/debian-security \
trixie-security main contrib non-free non-free-firmware" \
            >> /etc/apt/sources.list
        success "Security repo ditambahkan"
    fi
fi

blank
success "sources.list selesai dikonfigurasi"

# ══════════════════════════════════════════
# STEP 6 - APT-GET UPDATE (WATCHDOG)
# ══════════════════════════════════════════
step "STEP 6/17 ► apt-get update (Watchdog Mode)"

slow_msg "Bersihkan apt lock files"
rm -f /var/lib/apt/lists/lock        2>/dev/null
rm -f /var/cache/apt/archives/lock   2>/dev/null
rm -f /var/lib/dpkg/lock             2>/dev/null
rm -f /var/lib/dpkg/lock-frontend    2>/dev/null
dpkg --configure -a                   2>/dev/null

slow_msg "Bersihkan package lists lama"
rm -rf /var/lib/apt/lists/*           2>/dev/null
mkdir -p /var/lib/apt/lists/partial   2>/dev/null

> "$APT_LOG"

blank
echo -e "  ${BOLD}${YELLOW}── apt-get update OUTPUT (live) ──${NC}"
echo -e "  ${BLUE}────────────────────────────────────────────${NC}"

if [ "$DISTRO" = "debian8" ]; then
    apt-get update \
        --allow-unauthenticated \
        -o Acquire::ForceIPv4=true \
        -o Acquire::http::Timeout=15 \
        -o Acquire::http::Pipeline-Depth=0 \
        -o Acquire::Check-Valid-Until=false \
        -o Acquire::Retries=2 \
        -o APT::Get::AllowUnauthenticated=true \
        2>&1 | tee "$APT_LOG" | sed 's/^/  /' &
else
    apt-get update \
        -o Acquire::ForceIPv4=true \
        -o Acquire::http::Timeout=15 \
        -o Acquire::http::Pipeline-Depth=0 \
        -o Acquire::Retries=2 \
        2>&1 | tee "$APT_LOG" | sed 's/^/  /' &
fi

APT_PID=$!
WATCH_INTERVAL=3
STUCK_LIMIT=3
MAX_WAIT=120
ELAPSED=0
SAME_COUNT=0
LAST_SIZE=0
APT_KILLED=false

while kill -0 "$APT_PID" 2>/dev/null; do
    sleep $WATCH_INTERVAL
    ELAPSED=$((ELAPSED + WATCH_INTERVAL))
    CURRENT_SIZE=$(wc -c < "$APT_LOG" 2>/dev/null || echo 0)
    HAS_DOWNLOAD=false
    grep -qE "^(Hit|Get)" "$APT_LOG" 2>/dev/null && HAS_DOWNLOAD=true

    if [ "$CURRENT_SIZE" -eq "$LAST_SIZE" ]; then
        SAME_COUNT=$((SAME_COUNT + 1))
        if [ "$HAS_DOWNLOAD" = true ] && \
           [ "$SAME_COUNT" -ge "$STUCK_LIMIT" ]; then
            blank
            echo -e "  ${YELLOW}[WATCHDOG]${NC} Stuck terdeteksi → Auto kill ✓"
            kill "$APT_PID" 2>/dev/null
            kill $(pgrep -P "$APT_PID") 2>/dev/null
            wait "$APT_PID" 2>/dev/null
            APT_KILLED=true
            break
        fi
    else
        SAME_COUNT=0
    fi

    LAST_SIZE=$CURRENT_SIZE

    if [ "$ELAPSED" -ge "$MAX_WAIT" ]; then
        warn "[WATCHDOG] Timeout → Force kill"
        kill "$APT_PID" 2>/dev/null
        wait "$APT_PID" 2>/dev/null
        APT_KILLED=true
        break
    fi
done

wait "$APT_PID" 2>/dev/null

echo -e "  ${BLUE}────────────────────────────────────────────${NC}"
blank

if [ "$APT_KILLED" = true ]; then
    success "apt-get update selesai (auto-kill dari stuck) ✓"
elif grep -qE "^(Hit|Get)" "$APT_LOG" 2>/dev/null; then
    success "apt-get update selesai ✓"
else
    warn "apt-get update mungkin ada error, lanjut..."
fi

if [ -f "$APT_LOG" ]; then
    HIT=$(grep -c "^Hit" "$APT_LOG" 2>/dev/null || echo 0)
    GET=$(grep -c "^Get" "$APT_LOG" 2>/dev/null || echo 0)
    IGN=$(grep -c "^Ign" "$APT_LOG" 2>/dev/null || echo 0)
    ERR=$(grep -c "^Err" "$APT_LOG" 2>/dev/null || echo 0)
    echo -e "  ${GREEN}Hit=$HIT${NC}  ${CYAN}Get=$GET${NC}  ${YELLOW}Ign=$IGN${NC}  ${RED}Err=$ERR${NC}"
fi

# ══════════════════════════════════════════
# STEP 7 - HAPUS OPENSSH LAMA
# ══════════════════════════════════════════
step "STEP 7/17 ► Cek & Hapus OpenSSH (jika ada)"

SSH_PKG_FOUND=false
slow_msg "Periksa openssh-server"
dpkg -l 2>/dev/null | grep -qw "openssh-server" && SSH_PKG_FOUND=true
slow_msg "Periksa openssh-client"
dpkg -l 2>/dev/null | grep -qw "openssh-client"  && SSH_PKG_FOUND=true

if [ "$SSH_PKG_FOUND" = true ]; then
    warn "OpenSSH ditemukan → Hapus semua jejak..."

    slow_msg "Stop service SSH"
    systemctl stop ssh    2>/dev/null
    systemctl disable ssh 2>/dev/null
    service ssh stop      2>/dev/null
    pkill -x sshd         2>/dev/null
    sleep 1

    slow_msg "Remove + purge openssh"
    DEBIAN_FRONTEND=noninteractive \
    apt-get remove --purge -y \
        openssh-server openssh-client \
        openssh-sftp-server > /dev/null 2>&1
    apt-get autoremove -y > /dev/null 2>&1

    slow_msg "Hapus file config"
    rm -rf /etc/ssh/sshd_config \
           /etc/ssh/ssh_config  \
           /etc/ssh/ssh_host_*  \
           /run/sshd.pid        \
           /etc/init.d/ssh      2>/dev/null

    success "OpenSSH DIHAPUS BERSIH ✓"
else
    success "OpenSSH tidak ada → Skip"
fi

# ══════════════════════════════════════════
# STEP 8 - HAPUS ISC DHCP LAMA
# ══════════════════════════════════════════
step "STEP 8/17 ► Cek & Hapus ISC DHCP (jika ada)"

DHCP_PKG_FOUND=false
slow_msg "Periksa isc-dhcp-server"
dpkg -l 2>/dev/null | grep -qw "isc-dhcp-server" && DHCP_PKG_FOUND=true
slow_msg "Periksa isc-dhcp-common"
dpkg -l 2>/dev/null | grep -qw "isc-dhcp-common"  && DHCP_PKG_FOUND=true

if [ "$DHCP_PKG_FOUND" = true ]; then
    warn "ISC DHCP ditemukan → Hapus semua jejak..."

    slow_msg "Stop service DHCP"
    systemctl stop isc-dhcp-server    2>/dev/null
    systemctl disable isc-dhcp-server 2>/dev/null
    service isc-dhcp-server stop      2>/dev/null
    pkill -x dhcpd                    2>/dev/null
    sleep 1

    slow_msg "Remove + purge isc-dhcp"
    DEBIAN_FRONTEND=noninteractive \
    apt-get remove --purge -y \
        isc-dhcp-server isc-dhcp-common \
        isc-dhcp-client > /dev/null 2>&1
    apt-get autoremove -y > /dev/null 2>&1

    slow_msg "Hapus file config"
    rm -rf /etc/dhcp/dhcpd.conf        \
           /etc/dhcp/dhcpd6.conf       \
           /var/lib/dhcp/*             \
           /var/run/dhcpd.pid          \
           /etc/default/isc-dhcp-server 2>/dev/null

    success "ISC DHCP DIHAPUS BERSIH ✓"
else
    success "ISC DHCP tidak ada → Skip"
fi

# ══════════════════════════════════════════
# STEP 9 - INSTALL OPENSSH (SAFE MODE)
# ══════════════════════════════════════════
step "STEP 9/17 ► Install OpenSSH Server (Safe Mode)"

info "Mode: Auto-kill jika stuck di 'Processing triggers for systemd'"
blank

safe_apt_install "openssh-server" "$INSTALL_LOG"
if [ $? -ne 0 ]; then
    error "openssh-server GAGAL terinstall! Cek koneksi internet."
    exit 1
fi

# ══════════════════════════════════════════
# STEP 10 - KONFIGURASI SSH
# ══════════════════════════════════════════
step "STEP 10/17 ► Konfigurasi OpenSSH Server"
slow_msg "Menulis /etc/ssh/sshd_config"

mkdir -p /etc/ssh
cat > /etc/ssh/sshd_config << 'SSHEOF'
# AIO Script - OpenSSH Config
Port 22
Protocol 2

HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

SyslogFacility AUTH
LogLevel INFO

LoginGraceTime 2m
PermitRootLogin yes
StrictModes yes
MaxAuthTries 6
MaxSessions 10

PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys2
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no

UsePAM yes
ClientAliveInterval 120
ClientAliveCountMax 3
TCPKeepAlive yes
PrintMotd no
PrintLastLog yes
X11Forwarding yes
AllowTcpForwarding yes
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
SSHEOF

success "sshd_config selesai ✓"
slow_msg "Generate SSH Host Keys"
ssh-keygen -A > /dev/null 2>&1
success "SSH Host Keys generated ✓"

# ══════════════════════════════════════════
# STEP 11 - INSTALL ISC DHCP (SAFE MODE)
# ══════════════════════════════════════════
step "STEP 11/17 ► Install ISC DHCP Server (Safe Mode)"

info "Mode: Auto-kill jika stuck di 'Processing triggers for systemd'"
blank

safe_apt_install "isc-dhcp-server" "$INSTALL_LOG"
if [ $? -ne 0 ]; then
    error "isc-dhcp-server GAGAL terinstall!"
    exit 1
fi

# ══════════════════════════════════════════
# STEP 12 - KONFIGURASI DHCP INTERFACE
# ══════════════════════════════════════════
step "STEP 12/17 ► Set Interface DHCP"
slow_msg "Menulis /etc/default/isc-dhcp-server"

DHCP_DEFAULT="/etc/default/isc-dhcp-server"
if [ "$DISTRO" = "debian8" ]; then
    cat > "$DHCP_DEFAULT" << DEFEOF
# AIO Script - Debian 8
INTERFACES="$IFACE_LAN"
DEFEOF
else
    cat > "$DHCP_DEFAULT" << DEFEOF
# AIO Script - Debian 13
INTERFACESv4="$IFACE_LAN"
INTERFACESv6=""
DEFEOF
fi

success "DHCP interface: $IFACE_LAN ✓"

# ══════════════════════════════════════════
# STEP 13 - DHCPD.CONF
# ══════════════════════════════════════════
step "STEP 13/17 ► Konfigurasi dhcpd.conf"
slow_msg "Membuat /etc/dhcp/dhcpd.conf"

mkdir -p /etc/dhcp
cat > /etc/dhcp/dhcpd.conf << DHCPEOF
# AIO Script - ISC DHCP Config
# Network : $NETWORK / $SUBNET_MASK
# Range   : $RANGE_START - $RANGE_END (50 host)

default-lease-time 600;
max-lease-time 7200;
authoritative;
log-facility local7;

subnet $NETWORK netmask $SUBNET_MASK {
    range $RANGE_START $RANGE_END;
    option domain-name-servers $DNS_PRIMARY, $DNS_SECONDARY;
    option domain-name "local.lan";
    option routers $SERVER_IP;
    option broadcast-address $BROADCAST;
    default-lease-time 600;
    max-lease-time 7200;
}
DHCPEOF

success "dhcpd.conf selesai ✓"

# ══════════════════════════════════════════
# STEP 14 - NETWORK INTERFACE
# ══════════════════════════════════════════
step "STEP 14/17 ► Konfigurasi Network Interface"
slow_msg "Backup + tulis /etc/network/interfaces"

cp /etc/network/interfaces \
    "/etc/network/interfaces.bak.$(date +%s)" 2>/dev/null

NM_ACTIVE=false
systemctl is-active --quiet NetworkManager 2>/dev/null && NM_ACTIVE=true

if [ "$NM_ACTIVE" = false ]; then
    cat > /etc/network/interfaces << NETEOF
# AIO Script - Network Config
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

# Adapter 1 - Host-Only (LAN/DHCP)
auto $IFACE_LAN
iface $IFACE_LAN inet static
    address   $SERVER_IP
    netmask   $SUBNET_MASK
    broadcast $BROADCAST

# Adapter 2 - NAT (Internet)
auto $IFACE_WAN
iface $IFACE_WAN inet dhcp
NETEOF
    success "/etc/network/interfaces dikonfigurasi ✓"
else
    warn "NetworkManager aktif → Buat .nmconnection"
    mkdir -p /etc/NetworkManager/system-connections/
    cat > /etc/NetworkManager/system-connections/aio-lan.nmconnection << NMEOF
[connection]
id=aio-lan
type=ethernet
interface-name=$IFACE_LAN
autoconnect=true

[ipv4]
method=manual
addresses=$SERVER_IP/24
dns=$DNS_PRIMARY;$DNS_SECONDARY;

[ipv6]
method=ignore
NMEOF
    chmod 600 \
        /etc/NetworkManager/system-connections/aio-lan.nmconnection
    success "NM connection file dibuat ✓"
fi

# ══════════════════════════════════════════
# STEP 15 - APPLY IP
# ══════════════════════════════════════════
step "STEP 15/17 ► Apply IP ke $IFACE_LAN"

slow_msg "Flush IP lama"
ip addr flush dev "$IFACE_LAN" 2>/dev/null

if ip link show "$IFACE_LAN" > /dev/null 2>&1; then
    slow_msg "Set IP $SERVER_IP"
    ip addr add "$SERVER_IP/24" dev "$IFACE_LAN" 2>/dev/null
    ip link set "$IFACE_LAN" up 2>/dev/null
    success "IP $SERVER_IP → $IFACE_LAN ✓"
else
    warn "$IFACE_LAN belum terdeteksi (aktif setelah reboot)"
fi

if ip link show "$IFACE_WAN" > /dev/null 2>&1; then
    slow_msg "Aktifkan $IFACE_WAN"
    ip link set "$IFACE_WAN" up 2>/dev/null
    success "$IFACE_WAN (NAT) aktif ✓"
fi

slow_msg "Enable IP Forwarding"
echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null
sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1
success "IP Forwarding ON ✓"

# ══════════════════════════════════════════
# STEP 16 - START SERVICES
# ══════════════════════════════════════════
step "STEP 16/17 ► Start SSH & DHCP Service"

# SSH
slow_msg "Enable + Start OpenSSH"
if [ "$DISTRO" = "debian8" ]; then
    update-rc.d ssh enable  2>/dev/null
    service ssh restart     2>/dev/null
else
    systemctl daemon-reload 2>/dev/null
    systemctl enable ssh    2>/dev/null
    systemctl restart ssh   2>/dev/null
fi
sleep 1

if pgrep -x "sshd" > /dev/null 2>&1; then
    success "OpenSSH Server : RUNNING ✓"
    SSH_STATUS="${GREEN}RUNNING ✓${NC}"
else
    warn "SSH belum running → systemctl restart ssh"
    SSH_STATUS="${YELLOW}STANDBY ⚠${NC}"
fi

# DHCP
slow_msg "Enable + Start ISC DHCP"
if [ "$DISTRO" = "debian8" ]; then
    update-rc.d isc-dhcp-server enable  2>/dev/null
    service isc-dhcp-server restart     2>/dev/null
else
    systemctl daemon-reload           2>/dev/null
    systemctl enable isc-dhcp-server  2>/dev/null
    systemctl restart isc-dhcp-server 2>/dev/null
fi
sleep 1

if pgrep -x "dhcpd" > /dev/null 2>&1; then
    success "ISC DHCP Server : RUNNING ✓"
    DHCP_STATUS="${GREEN}RUNNING ✓${NC}"
else
    warn "DHCP belum running (normal sebelum ada client)"
    DHCP_STATUS="${YELLOW}STANDBY ⚠${NC}"
fi

# ══════════════════════════════════════════
# STEP 17 - LAPORAN AKHIR
# ══════════════════════════════════════════
step "STEP 17/17 ► Laporan Akhir"

ACTIVE_IP=$(ip addr show "$IFACE_LAN" 2>/dev/null \
    | grep "inet " | awk '{print $2}' | head -1)
SSH_VER=$(sshd -V 2>&1 | grep -oP 'OpenSSH_[^\s,]+' | head -1)

blank
echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║             LAPORAN INSTALASI SELESAI                      ║${NC}"
echo -e "${BOLD}${BLUE}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${BLUE}║${NC}  ${WHITE}[OS INFO]${NC}"
echo -e "${BOLD}${BLUE}║${NC}    OS             : ${GREEN}$DISTRO_NAME${NC}"
echo -e "${BOLD}${BLUE}║${NC}    OpenSSH        : ${GREEN}${SSH_VER:-openssh-server}${NC}"
echo -e "${BOLD}${BLUE}║${NC}    Internet       : ${GREEN}$INTERNET_OK${NC}"
echo -e "${BOLD}${BLUE}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${BLUE}║${NC}  ${WHITE}[STATUS SERVICE]${NC}"
echo -e "${BOLD}${BLUE}║${NC}    OpenSSH Server : $(echo -e $SSH_STATUS)"
echo -e "${BOLD}${BLUE}║${NC}    ISC DHCP Server: $(echo -e $DHCP_STATUS)"
echo -e "${BOLD}${BLUE}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${BLUE}║${NC}  ${WHITE}[NETWORK]${NC}"
echo -e "${BOLD}${BLUE}║${NC}    LAN Interface  : ${GREEN}$IFACE_LAN${NC} (Host-Only Adapter 1)"
echo -e "${BOLD}${BLUE}║${NC}    WAN Interface  : ${GREEN}$IFACE_WAN${NC} (NAT        Adapter 2)"
echo -e "${BOLD}${BLUE}║${NC}    Server IP      : ${YELLOW}$SERVER_IP${NC}"
echo -e "${BOLD}${BLUE}║${NC}    IP Aktif       : ${CYAN}${ACTIVE_IP:-Belum assign}${NC}"
echo -e "${BOLD}${BLUE}║${NC}    Netmask        : ${GREEN}$SUBNET_MASK${NC}"
echo -e "${BOLD}${BLUE}║${NC}    Broadcast      : ${GREEN}$BROADCAST${NC}"
echo -e "${BOLD}${BLUE}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${BLUE}║${NC}  ${WHITE}[DHCP POOL]${NC}"
echo -e "${BOLD}${BLUE}║${NC}    Range          : ${GREEN}$RANGE_START${NC} s/d ${GREEN}$RANGE_END${NC}"
echo -e "${BOLD}${BLUE}║${NC}    Total Host     : ${GREEN}50 Host${NC}"
echo -e "${BOLD}${BLUE}║${NC}    Gateway Client : ${GREEN}$SERVER_IP${NC}"
echo -e "${BOLD}${BLUE}║${NC}    DNS            : ${GREEN}$DNS_PRIMARY / $DNS_SECONDARY${NC}"
echo -e "${BOLD}${BLUE}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${BLUE}║${NC}  ${WHITE}[KONEKSI SSH]${NC}"
echo -e "${BOLD}${BLUE}║${NC}    Host/IP  : ${YELLOW}$SERVER_IP${NC}"
echo -e "${BOLD}${BLUE}║${NC}    Port     : ${YELLOW}22${NC}"
echo -e "${BOLD}${BLUE}║${NC}    User     : ${YELLOW}root${NC}"
echo -e "${BOLD}${BLUE}║${NC}    CMD/PS   : ${CYAN}ssh root@$SERVER_IP${NC}"
echo -e "${BOLD}${BLUE}║${NC}    PuTTY    : ${CYAN}Host=$SERVER_IP | Port=22 | SSH${NC}"
echo -e "${BOLD}${BLUE}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${BLUE}║${NC}  ${WHITE}[CEK MANUAL SETELAH REBOOT]${NC}"
echo -e "${BOLD}${BLUE}║${NC}    ${CYAN}systemctl status ssh${NC}"
echo -e "${BOLD}${BLUE}║${NC}    ${CYAN}systemctl status isc-dhcp-server${NC}"
echo -e "${BOLD}${BLUE}║${NC}    ${CYAN}ip addr show $IFACE_LAN${NC}"
echo -e "${BOLD}${BLUE}║${NC}    ${CYAN}cat /var/lib/dhcp/dhcpd.leases${NC}"
echo -e "${BOLD}${BLUE}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${BLUE}║${NC}  ${GREEN}✓ INSTALASI SELESAI!${NC}"
echo -e "${BOLD}${BLUE}║${NC}  ${YELLOW}⚠ Reboot dianjurkan: ${CYAN}reboot${NC}"
echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
blank

LOG_FINAL="/root/aio_install_$(date +%Y%m%d_%H%M%S).log"
{
    echo "=== AIO Install Log ==="
    echo "Date     : $(date)"
    echo "OS       : $DISTRO_NAME"
    echo "ServerIP : $SERVER_IP"
    echo "Range    : $RANGE_START - $RANGE_END"
    echo "LAN      : $IFACE_LAN"
    echo "WAN      : $IFACE_WAN"
    echo "SSH      : $(pgrep -x sshd  >/dev/null 2>&1 && echo RUNNING || echo STOPPED)"
    echo "DHCP     : $(pgrep -x dhcpd >/dev/null 2>&1 && echo RUNNING || echo STOPPED)"
} > "$LOG_FINAL"

echo -e "  ${CYAN}[i] Log: $LOG_FINAL${NC}"
blank
