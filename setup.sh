#!/bin/bash

# ================================================================
#  ALL-IN-ONE INSTALLER: OpenSSH Server + ISC DHCP Server
#  Compatible   : Debian 8 (Jessie) / Debian 13 (Trixie)
#  VirtualBox   : Adapter1 = Host-Only | Adapter2 = NAT
#  Fix          : Spinner apt-get, Random IP tersimpan,
#                 Cek repo hidup, Hapus duplikat otomatis
# ================================================================

# ──────────────────────────────
#  WARNA OUTPUT
# ──────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# ──────────────────────────────
#  FILE PENYIMPAN IP (agar tidak random ulang)
# ──────────────────────────────
IP_SAVE_FILE="/root/.aio_server_ip"
APT_LOG="/tmp/apt_update_aio.log"

# ──────────────────────────────
#  FUNGSI TAMPILAN
# ──────────────────────────────
info()    { echo -e "  ${CYAN}[INFO]${NC}  $1"; sleep 0.3; }
success() { echo -e "  ${GREEN}[OK]${NC}    $1"; sleep 0.3; }
warn()    { echo -e "  ${YELLOW}[WARN]${NC}   $1"; sleep 0.3; }
error()   { echo -e "  ${RED}[ERROR]${NC}  $1"; sleep 0.3; }
divider() { echo -e "${BLUE}  ────────────────────────────────────────────${NC}"; }

step() {
    echo ""
    echo -e "${BOLD}${BLUE}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${BLUE}│${NC} ${WHITE}${BOLD} $1${NC}"
    echo -e "${BOLD}${BLUE}└─��───────────────────────────────────────────┘${NC}"
    sleep 0.4
}

# ──────────────────────────────
#  FUNGSI SPINNER (anti-freeze display)
# ──────────────────────────────
spinner_run() {
    local MSG="$1"
    shift
    local CMD="$@"
    local SPINNERS=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0

    eval "$CMD" > /tmp/spinner_out.log 2>&1 &
    local PID=$!

    echo -ne "  ${CYAN}[~]${NC} $MSG "

    while kill -0 "$PID" 2>/dev/null; do
        echo -ne "\r  ${CYAN}[~]${NC} $MSG ${YELLOW}${SPINNERS[$i]}${NC} "
        i=$(( (i+1) % ${#SPINNERS[@]} ))
        sleep 0.2
    done

    wait "$PID"
    local EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        echo -e "\r  ${GREEN}[OK]${NC}  $MSG ${GREEN}✓${NC}          "
    else
        echo -e "\r  ${RED}[!!]${NC}  $MSG ${RED}✗${NC}          "
    fi

    return $EXIT_CODE
}

slow_msg() {
    local msg="$1"
    echo -ne "  ${CYAN}[~]${NC} $msg "
    for i in {1..5}; do
        echo -ne "${YELLOW}.${NC}"
        sleep 0.4
    done
    echo -e " ${GREEN}✓${NC}"
}

# ──────────────────────────────
#  BANNER
# ──────────────────────────────
banner() {
    clear
    echo -e "${BLUE}"
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║      AIO Installer: OpenSSH + ISC DHCP Server     ║"
    echo "  ╠═══════════════════════════════════════════════════╣"
    echo "  ║  Debian 8 (Jessie) / Debian 13 (Trixie)           ║"
    echo "  ║  VirtualBox  : Adapter1=Host-Only | Adapter2=NAT  ║"
    echo "  ║  DHCP Range  : 50 Host                            ║"
    echo "  ║  Repo Check  : Kambing + Fallback Auto            ║"
    echo "  ║  IP Saved    : Tidak akan random ulang            ║"
    echo "  ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    sleep 1
}

# ══════════════════════════════════════════════
# [CEK] ROOT
# ══════════════════════════════════════════════
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[!] Harus dijalankan sebagai ROOT!${NC}"
    echo -e "${YELLOW}    Gunakan: sudo bash $0${NC}"
    exit 1
fi

banner

# ══════════════════════════════════════════════
# STEP 1 : DETEKSI VERSI DEBIAN
# ══════════════════════════════════════════════
step "STEP 1 ► Deteksi Versi Debian"
slow_msg "Membaca informasi sistem"

DEBIAN_VER_NUM=$(cat /etc/debian_version 2>/dev/null | cut -d'.' -f1)
DEBIAN_CODENAME=$(grep VERSION_CODENAME /etc/os-release 2>/dev/null | cut -d'=' -f2 | tr -d '"')

# Fallback lsb_release
if [ -z "$DEBIAN_CODENAME" ]; then
    DEBIAN_CODENAME=$(lsb_release -cs 2>/dev/null)
fi

if [[ "$DEBIAN_VER_NUM" == "8" ]] || [[ "$DEBIAN_CODENAME" == "jessie" ]]; then
    DISTRO="debian8"
    DISTRO_NAME="Debian 8 (Jessie)"
    IFACE_LAN="eth0"
    IFACE_WAN="eth1"
elif [[ "$DEBIAN_VER_NUM" == "13" ]] || [[ "$DEBIAN_CODENAME" == "trixie" ]]; then
    DISTRO="debian13"
    DISTRO_NAME="Debian 13 (Trixie)"
    IFACE_LAN="enp0s3"
    IFACE_WAN="enp0s8"
else
    warn "Versi tidak dikenal ($DEBIAN_VER_NUM / $DEBIAN_CODENAME)"
    warn "Default ke Debian 13 mode"
    DISTRO="debian13"
    DISTRO_NAME="Debian (Unknown - Default 13)"
    IFACE_LAN="enp0s3"
    IFACE_WAN="enp0s8"
fi

success "OS Terdeteksi : $DISTRO_NAME"
success "LAN (Adp1)    : $IFACE_LAN → Host-Only"
success "WAN (Adp2)    : $IFACE_WAN → NAT"

# ══════════════════════════════════════════════
# STEP 2 : CEK / LOAD IP (tidak random ulang)
# ══════════════════════════════════════════════
step "STEP 2 ► Load / Generate IP Server"

if [ -f "$IP_SAVE_FILE" ]; then
    # ── IP sudah tersimpan, load saja ──
    source "$IP_SAVE_FILE"
    echo ""
    echo -e "  ${GREEN}[IP TERSIMPAN DITEMUKAN]${NC} - Tidak akan generate ulang"
    divider
    success "Server IP    : $SERVER_IP"
    success "Network      : $NETWORK/24"
    success "DHCP Range   : $RANGE_START - $RANGE_END (50 host)"
    divider
else
    # ── Belum ada, generate random sekali ──
    slow_msg "Generate IP acak (hanya sekali)"

    RANDOM_OCT=$((RANDOM % 200 + 20))

    SERVER_IP="192.168.$RANDOM_OCT.1"
    NETWORK="192.168.$RANDOM_OCT.0"
    SUBNET_MASK="255.255.255.0"
    BROADCAST="192.168.$RANDOM_OCT.255"
    RANGE_START="192.168.$RANDOM_OCT.100"
    RANGE_END="192.168.$RANDOM_OCT.150"
    DNS_PRIMARY="8.8.8.8"
    DNS_SECONDARY="8.8.4.4"

    # Simpan ke file agar tidak random ulang
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

    echo ""
    echo -e "  ${YELLOW}[IP BARU DIGENERATE & DISIMPAN]${NC}"
    echo -e "  ${CYAN}File: $IP_SAVE_FILE${NC}"
    divider
    success "Server IP    : $SERVER_IP"
    success "Network      : $NETWORK/24"
    success "Netmask      : $SUBNET_MASK"
    success "Broadcast    : $BROADCAST"
    success "DHCP Range   : $RANGE_START - $RANGE_END"
    success "Total Host   : 50 Host"
    success "Gateway      : $SERVER_IP"
    success "DNS          : $DNS_PRIMARY, $DNS_SECONDARY"
    divider
fi

# Pastikan variabel tersedia dari file jika baru saja di-source
DNS_PRIMARY="${DNS_PRIMARY:-8.8.8.8}"
DNS_SECONDARY="${DNS_SECONDARY:-8.8.4.4}"

# ══════════════════════════════════════════════
# STEP 3 : CEK REPO HIDUP (Kambing / Fallback)
# ══════════════════════════════════════════════
step "STEP 3 ► Cek Status Repository"

check_url() {
    # Return 0 = hidup, 1 = mati
    local URL="$1"
    local TIMEOUT=8
    if command -v curl &>/dev/null; then
        curl --silent --max-time $TIMEOUT --head "$URL" > /dev/null 2>&1
        return $?
    elif command -v wget &>/dev/null; then
        wget --quiet --timeout=$TIMEOUT --spider "$URL" > /dev/null 2>&1
        return $?
    else
        # Fallback: nc / ping domain saja
        local HOST=$(echo "$URL" | awk -F/ '{print $3}')
        ping -c 1 -W $TIMEOUT "$HOST" > /dev/null 2>&1
        return $?
    fi
}

if [ "$DISTRO" = "debian8" ]; then
    echo ""
    info "Memeriksa repo untuk Debian 8..."

    # ── Cek Kambing UI ──
    slow_msg "Cek kambing.ui.ac.id"
    KAMBING_UP=false
    if check_url "http://kambing.ui.ac.id/debian/"; then
        KAMBING_UP=true
        success "kambing.ui.ac.id    → HIDUP ✓"
    else
        warn "kambing.ui.ac.id    → MATI / TIMEOUT ✗"
    fi

    # ── Cek archive.debian.org ──
    slow_msg "Cek archive.debian.org"
    ARCHIVE_UP=false
    if check_url "http://archive.debian.org/debian/"; then
        ARCHIVE_UP=true
        success "archive.debian.org  → HIDUP ✓"
    else
        warn "archive.debian.org  → MATI / TIMEOUT ✗"
    fi

    # ── Cek Repo ID alternatif ──
    slow_msg "Cek ftp.id.debian.org"
    FTPID_UP=false
    if check_url "http://ftp.id.debian.org/debian/"; then
        FTPID_UP=true
        success "ftp.id.debian.org   → HIDUP ✓"
    else
        warn "ftp.id.debian.org   → MATI / TIMEOUT ✗"
    fi

    # ── Pilih repo yang hidup ──
    echo ""
    info "Menyusun sources.list berdasarkan status repo..."

    SOURCES_CONTENT=""

    if [ "$KAMBING_UP" = true ]; then
        SOURCES_CONTENT+="# Kambing UI Mirror (AKTIF)\n"
        SOURCES_CONTENT+="deb http://kambing.ui.ac.id/debian/ jessie main contrib non-free\n"
        SOURCES_CONTENT+="deb http://kambing.ui.ac.id/debian/ jessie-updates main contrib non-free\n\n"
        success "Menggunakan: kambing.ui.ac.id (prioritas utama)"
    fi

    if [ "$ARCHIVE_UP" = true ]; then
        SOURCES_CONTENT+="# Official Debian Archive (Jessie EOL)\n"
        SOURCES_CONTENT+="deb http://archive.debian.org/debian/ jessie main contrib non-free\n"
        SOURCES_CONTENT+="deb http://archive.debian.org/debian-security jessie/updates main contrib non-free\n\n"
        success "Menggunakan: archive.debian.org"
    fi

    if [ "$FTPID_UP" = true ]; then
        SOURCES_CONTENT+="# FTP ID Debian Mirror\n"
        SOURCES_CONTENT+="deb http://ftp.id.debian.org/debian/ jessie main contrib non-free\n\n"
        success "Menggunakan: ftp.id.debian.org (backup)"
    fi

    # Jika semua mati, paksa archive.debian.org
    if [ "$KAMBING_UP" = false ] && [ "$ARCHIVE_UP" = false ] && [ "$FTPID_UP" = false ]; then
        warn "SEMUA repo tidak dapat dijangkau!"
        warn "Memakai archive.debian.org secara paksa..."
        SOURCES_CONTENT="# Forced Fallback - Debian 8\n"
        SOURCES_CONTENT+="deb http://archive.debian.org/debian/ jessie main contrib non-free\n"
        SOURCES_CONTENT+="deb http://archive.debian.org/debian-security jessie/updates main contrib non-free\n"
    fi

    # Tulis sources.list
    cp /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null
    printf "$SOURCES_CONTENT" > /etc/apt/sources.list
    success "sources.list berhasil ditulis"

    # APT config untuk Debian 8 (EOL bypass)
    cat > /etc/apt/apt.conf.d/99debian8-fix << 'APTEOF'
Acquire::Check-Valid-Until "false";
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
Acquire::ForceIPv4 "true";
APT::Get::AllowUnauthenticated "true";
Acquire::http::Timeout "30";
Acquire::Retries "3";
APTEOF
    success "APT config Debian 8 (EOL bypass) diterapkan"

elif [ "$DISTRO" = "debian13" ]; then
    echo ""
    info "Memeriksa repo untuk Debian 13..."

    # ── Cek deb.debian.org ──
    slow_msg "Cek deb.debian.org"
    DEBMAIN_UP=false
    if check_url "http://deb.debian.org/debian/"; then
        DEBMAIN_UP=true
        success "deb.debian.org      → HIDUP ✓"
    else
        warn "deb.debian.org      → MATI / TIMEOUT ✗"
    fi

    # ── Cek ftp.debian.org ──
    slow_msg "Cek ftp.debian.org"
    FTPDEB_UP=false
    if check_url "http://ftp.debian.org/debian/"; then
        FTPDEB_UP=true
        success "ftp.debian.org      → HIDUP ✓"
    else
        warn "ftp.debian.org      → MATI / TIMEOUT ✗"
    fi

    # ── Cek security.debian.org ──
    slow_msg "Cek security.debian.org"
    SECDEB_UP=false
    if check_url "http://security.debian.org/"; then
        SECDEB_UP=true
        success "security.debian.org → HIDUP ✓"
    else
        warn "security.debian.org → MATI / TIMEOUT ✗"
    fi

    # ── Susun sources.list ──
    echo ""
    cp /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null

    # Pilih mirror utama
    if [ "$DEBMAIN_UP" = true ]; then
        MAIN_MIRROR="http://deb.debian.org/debian/"
        success "Mirror utama: deb.debian.org"
    elif [ "$FTPDEB_UP" = true ]; then
        MAIN_MIRROR="http://ftp.debian.org/debian/"
        success "Mirror utama: ftp.debian.org (fallback)"
    else
        MAIN_MIRROR="http://deb.debian.org/debian/"
        warn "Semua mirror timeout - paksa deb.debian.org"
    fi

    # Tulis sources.list
    cat > /etc/apt/sources.list << REPOEOF
# Debian 13 (Trixie) - Main
deb $MAIN_MIRROR trixie main contrib non-free non-free-firmware
deb $MAIN_MIRROR trixie-updates main contrib non-free non-free-firmware
REPOEOF

    if [ "$SECDEB_UP" = true ]; then
        echo "deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware" \
            >> /etc/apt/sources.list
        success "Security repo ditambahkan"
    fi

    # APT config Debian 13
    cat > /etc/apt/apt.conf.d/99debian13-fix << 'APTEOF'
Acquire::ForceIPv4 "true";
Acquire::http::Timeout "30";
Acquire::Retries "3";
APTEOF
    success "APT config Debian 13 diterapkan"
fi

# ══════════════════════════════════════════════
# STEP 4 : APT-GET UPDATE (dengan spinner)
# ══════════════════════════════════════════════
step "STEP 4 ► Update Package List"

run_apt_update() {
    local SPINNERS=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0

    if [ "$DISTRO" = "debian8" ]; then
        apt-get update \
            --allow-unauthenticated \
            -o Acquire::ForceIPv4=true \
            -o Acquire::http::Timeout=30 \
            -o Acquire::Check-Valid-Until=false \
            -o Acquire::Retries=3 \
            > "$APT_LOG" 2>&1 &
    else
        apt-get update \
            -o Acquire::ForceIPv4=true \
            -o Acquire::http::Timeout=30 \
            -o Acquire::Retries=3 \
            > "$APT_LOG" 2>&1 &
    fi

    local PID=$!
    echo -ne "  ${CYAN}[~]${NC} Menjalankan apt-get update "

    while kill -0 "$PID" 2>/dev/null; do
        echo -ne "\r  ${CYAN}[~]${NC} Menjalankan apt-get update ${YELLOW}${SPINNERS[$i]}${NC} "
        i=$(( (i+1) % ${#SPINNERS[@]} ))
        sleep 0.25
    done

    wait "$PID"
    local EXIT=$?
    echo ""

    # Tampilkan ringkasan
    if [ -f "$APT_LOG" ]; then
        local HIT=$(grep -c "^Hit"  "$APT_LOG" 2>/dev/null || echo 0)
        local GET=$(grep -c "^Get"  "$APT_LOG" 2>/dev/null || echo 0)
        local IGN=$(grep -c "^Ign"  "$APT_LOG" 2>/dev/null || echo 0)
        local ERR=$(grep -c "^Err"  "$APT_LOG" 2>/dev/null || echo 0)
        echo -e "  ${GREEN}Hit${NC}: $HIT  ${CYAN}Get${NC}: $GET  ${YELLOW}Ign${NC}: $IGN  ${RED}Err${NC}: $ERR"
    fi

    # Anggap sukses jika ada Hit/Get (meski exit code != 0)
    if [ $EXIT -eq 0 ] || grep -qE "^(Hit|Get)" "$APT_LOG" 2>/dev/null; then
        success "apt-get update selesai"
        return 0
    else
        error "apt-get update gagal"
        if [ -f "$APT_LOG" ]; then
            echo -e "  ${RED}--- 5 baris terakhir log ---${NC}"
            tail -5 "$APT_LOG" | sed 's/^/  /'
        fi
        return 1
    fi
}

# Jalankan update
run_apt_update
APT_RESULT=$?

if [ $APT_RESULT -ne 0 ]; then
    warn "Update gagal. Coba install package secara langsung..."
    warn "Script akan tetap lanjut (package mungkin sudah ada di cache)"
    sleep 1
fi

# ══════════════════════════════════════════════
# STEP 5 : HAPUS DUPLIKAT OPENSSH
# ══════════════════════════════════════════════
step "STEP 5 ► Cek & Bersihkan OpenSSH (jika ada)"

OPENSSH_FOUND=false
slow_msg "Memeriksa openssh-server"
if dpkg -l 2>/dev/null | grep -qw "openssh-server"; then
    OPENSSH_FOUND=true
fi
slow_msg "Memeriksa openssh-client"
if dpkg -l 2>/dev/null | grep -qw "openssh-client"; then
    OPENSSH_FOUND=true
fi

if [ "$OPENSSH_FOUND" = true ]; then
    warn "OpenSSH DITEMUKAN → Menghapus semua jejak..."

    slow_msg "Menghentikan service SSH"
    systemctl stop ssh          2>/dev/null
    systemctl disable ssh       2>/dev/null
    service ssh stop            2>/dev/null
    pkill -x sshd               2>/dev/null

    slow_msg "Menghapus package openssh"
    spinner_run "apt-get remove openssh" \
        "apt-get remove --purge -y openssh-server openssh-client openssh-sftp-server"

    slow_msg "Autoremove sisa dependensi"
    spinner_run "apt-get autoremove" \
        "apt-get autoremove -y"

    slow_msg "Hapus file konfigurasi SSH"
    rm -rf /etc/ssh/sshd_config     2>/dev/null
    rm -rf /etc/ssh/ssh_config      2>/dev/null
    rm -rf /etc/ssh/ssh_host_*      2>/dev/null
    rm -rf /etc/init.d/ssh          2>/dev/null
    rm -rf /run/sshd.pid            2>/dev/null

    slow_msg "apt-get purge openssh"
    apt-get purge -y openssh-server openssh-client > /dev/null 2>&1

    success "OpenSSH berhasil DIHAPUS bersih"
else
    success "OpenSSH tidak ditemukan → Langsung install"
fi

# ══════════════════════════════════════════════
# STEP 6 : HAPUS DUPLIKAT ISC DHCP
# ══════════════════════════════════════════════
step "STEP 6 ► Cek & Bersihkan ISC DHCP (jika ada)"

DHCP_FOUND=false
slow_msg "Memeriksa isc-dhcp-server"
if dpkg -l 2>/dev/null | grep -qw "isc-dhcp-server"; then
    DHCP_FOUND=true
fi
slow_msg "Memeriksa isc-dhcp-common"
if dpkg -l 2>/dev/null | grep -qw "isc-dhcp-common"; then
    DHCP_FOUND=true
fi

if [ "$DHCP_FOUND" = true ]; then
    warn "ISC DHCP DITEMUKAN → Menghapus semua jejak..."

    slow_msg "Menghentikan service DHCP"
    systemctl stop isc-dhcp-server      2>/dev/null
    systemctl disable isc-dhcp-server   2>/dev/null
    service isc-dhcp-server stop        2>/dev/null
    pkill -x dhcpd                      2>/dev/null

    slow_msg "Menghapus package isc-dhcp"
    spinner_run "apt-get remove isc-dhcp" \
        "apt-get remove --purge -y isc-dhcp-server isc-dhcp-common isc-dhcp-client"

    slow_msg "Autoremove sisa dependensi"
    spinner_run "apt-get autoremove dhcp" \
        "apt-get autoremove -y"

    slow_msg "Hapus file konfigurasi DHCP"
    rm -rf /etc/dhcp/dhcpd.conf         2>/dev/null
    rm -rf /etc/dhcp/dhcpd6.conf        2>/dev/null
    rm -rf /var/lib/dhcp/*              2>/dev/null
    rm -rf /var/run/dhcpd.pid           2>/dev/null
    rm -rf /etc/default/isc-dhcp-server 2>/dev/null

    slow_msg "apt-get purge isc-dhcp"
    apt-get purge -y isc-dhcp-server isc-dhcp-common > /dev/null 2>&1

    success "ISC DHCP Server berhasil DIHAPUS bersih"
else
    success "ISC DHCP tidak ditemukan → Langsung install"
fi

# ══════════════════════════════════════════════
# STEP 7 : INSTALL OPENSSH SERVER
# ══════════════════════════════════════════════
step "STEP 7 ► Install OpenSSH Server"

slow_msg "Mempersiapkan instalasi openssh-server"

spinner_run "Install openssh-server" \
    "env DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server"

if ! dpkg -l | grep -qw "openssh-server" 2>/dev/null; then
    error "openssh-server GAGAL terinstall!"
    error "Cek log: cat $APT_LOG"
    exit 1
fi

success "openssh-server berhasil diinstall"

# ══════════════════════════════════════════════
# STEP 8 : KONFIGURASI OPENSSH
# ══════════════════════════════════════════════
step "STEP 8 ► Konfigurasi OpenSSH Server"
slow_msg "Menulis /etc/ssh/sshd_config"

mkdir -p /etc/ssh

cat > /etc/ssh/sshd_config << 'SSHEOF'
# ================================================
# OpenSSH Server - Auto Config by AIO Script
# ================================================

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

# ── Auth ──
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys2
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no

# ── PAM ──
UsePAM yes

# ── Keepalive ──
ClientAliveInterval 120
ClientAliveCountMax 3
TCPKeepAlive yes

# ── Misc ──
PrintMotd no
PrintLastLog yes
X11Forwarding yes
AllowTcpForwarding yes
AcceptEnv LANG LC_*

# ── SFTP ──
Subsystem sftp /usr/lib/openssh/sftp-server
SSHEOF

success "sshd_config berhasil ditulis"

slow_msg "Generate SSH Host Keys"
ssh-keygen -A > /dev/null 2>&1
success "Host Keys berhasil digenerate"

# ══════════════════════════════════════════════
# STEP 9 : INSTALL ISC DHCP SERVER
# ══════════════════════════════════════════════
step "STEP 9 ► Install ISC DHCP Server"
slow_msg "Mempersiapkan instalasi isc-dhcp-server"

spinner_run "Install isc-dhcp-server" \
    "env DEBIAN_FRONTEND=noninteractive apt-get install -y isc-dhcp-server"

if ! dpkg -l | grep -qw "isc-dhcp-server" 2>/dev/null; then
    error "isc-dhcp-server GAGAL terinstall!"
    exit 1
fi

success "isc-dhcp-server berhasil diinstall"

# ══════════════════════════════════════════════
# STEP 10 : KONFIGURASI INTERFACE DHCP
# ══════════════════════════════════════════════
step "STEP 10 ► Set Interface DHCP"
slow_msg "Mengkonfigurasi /etc/default/isc-dhcp-server"

DHCP_DEFAULT="/etc/default/isc-dhcp-server"

# Tulis ulang file default
cat > "$DHCP_DEFAULT" << DEFEOF
# Generated by AIO Script
INTERFACESv4="$IFACE_LAN"
INTERFACESv6=""
DEFEOF

# Fallback untuk format lama (Debian 8)
if [ "$DISTRO" = "debian8" ]; then
    cat > "$DHCP_DEFAULT" << DEFEOF8
# Generated by AIO Script - Debian 8
INTERFACES="$IFACE_LAN"
DEFEOF8
fi

success "DHCP interface: $IFACE_LAN"

# ══════════════════════════════════════════════
# STEP 11 : KONFIGURASI DHCPD.CONF
# ══════════════════════════════════════════════
step "STEP 11 ► Konfigurasi dhcpd.conf"
slow_msg "Membuat /etc/dhcp/dhcpd.conf"

mkdir -p /etc/dhcp

cat > /etc/dhcp/dhcpd.conf << DHCPEOF
# ================================================
# ISC DHCP Server Configuration
# Generated by AIO Script
# Network : $NETWORK / 255.255.255.0
# Range   : $RANGE_START - $RANGE_END (50 host)
# ================================================

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

success "dhcpd.conf berhasil ditulis"

# ══════════════════════════════════════════════
# STEP 12 : KONFIGURASI NETWORK INTERFACE
# ══════════════════════════════════════════════
step "STEP 12 ► Konfigurasi Network Interface"
slow_msg "Backup & tulis /etc/network/interfaces"

# Backup
cp /etc/network/interfaces \
    "/etc/network/interfaces.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null

NM_ACTIVE=false
if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    NM_ACTIVE=true
fi

if [ "$NM_ACTIVE" = false ]; then
    cat > /etc/network/interfaces << NETEOF
# Generated by AIO Script
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

# Adapter 1 - Host-Only (DHCP Server Interface)
auto $IFACE_LAN
iface $IFACE_LAN inet static
    address     $SERVER_IP
    netmask     $SUBNET_MASK
    broadcast   $BROADCAST

# Adapter 2 - NAT (Internet)
auto $IFACE_WAN
iface $IFACE_WAN inet dhcp
NETEOF
    success "/etc/network/interfaces dikonfigurasi"

else
    warn "NetworkManager aktif - Buat connection file"
    mkdir -p /etc/NetworkManager/system-connections/

    cat > /etc/NetworkManager/system-connections/aio-host-only.nmconnection << NMEOF
[connection]
id=aio-host-only
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
    chmod 600 /etc/NetworkManager/system-connections/aio-host-only.nmconnection
    success "NetworkManager connection file dibuat"
fi

# ══════════════════════════════════════════════
# STEP 13 : APPLY IP KE INTERFACE
# ══════════════════════════════════════════════
step "STEP 13 ► Apply IP ke Interface $IFACE_LAN"

slow_msg "Flush IP lama"
ip addr flush dev "$IFACE_LAN" 2>/dev/null

slow_msg "Set IP $SERVER_IP"
if ip link show "$IFACE_LAN" > /dev/null 2>&1; then
    ip addr add "$SERVER_IP/24" dev "$IFACE_LAN" 2>/dev/null
    ip link set "$IFACE_LAN" up 2>/dev/null
    success "IP $SERVER_IP → $IFACE_LAN OK"
else
    warn "$IFACE_LAN belum ada. IP aktif setelah reboot / pasang kabel."
fi

slow_msg "Aktifkan interface WAN $IFACE_WAN"
if ip link show "$IFACE_WAN" > /dev/null 2>&1; then
    ip link set "$IFACE_WAN" up 2>/dev/null
    success "$IFACE_WAN (NAT) diaktifkan"
else
    warn "$IFACE_WAN belum terdeteksi"
fi

# ══════════════════════════════════════════════
# STEP 14 : FIREWALL & IP FORWARD
# ══════════════════════════════════════════════
step "STEP 14 ► Konfigurasi Firewall (iptables)"
slow_msg "Setting iptables rules"

iptables -A INPUT -i lo -j ACCEPT                          2>/dev/null
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
iptables -A INPUT -p tcp --dport 22 -j ACCEPT              2>/dev/null
iptables -A INPUT -p udp --dport 67 -j ACCEPT              2>/dev/null
iptables -A INPUT -p udp --dport 68 -j ACCEPT              2>/dev/null

slow_msg "Aktifkan IP Forwarding"
echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null
sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1

# Persist iptables
if command -v iptables-save > /dev/null 2>&1; then
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
fi

success "Port 22 (SSH) + Port 67/68 (DHCP) dibuka"
success "IP Forwarding aktif"

# ══════════════════════════════════════════════
# STEP 15 : START OPENSSH
# ══════════════════════════════════════════════
step "STEP 15 ► Enable & Start OpenSSH Server"
slow_msg "Enabling SSH service"

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
    success "OpenSSH Server ✓ RUNNING"
    SSH_STATUS="${GREEN}RUNNING ✓${NC}"
else
    warn "SSH mungkin belum aktif sepenuhnya"
    warn "Manual: systemctl restart ssh"
    SSH_STATUS="${YELLOW}STANDBY ⚠${NC}"
fi

# ══════════════════════════════════════════════
# STEP 16 : START ISC DHCP
# ══════════════════════════════════════════════
step "STEP 16 ► Enable & Start ISC DHCP Server"
slow_msg "Enabling DHCP service"

if [ "$DISTRO" = "debian8" ]; then
    update-rc.d isc-dhcp-server enable  2>/dev/null
    service isc-dhcp-server restart     2>/dev/null
else
    systemctl daemon-reload             2>/dev/null
    systemctl enable isc-dhcp-server    2>/dev/null
    systemctl restart isc-dhcp-server   2>/dev/null
fi

sleep 1

if pgrep -x "dhcpd" > /dev/null 2>&1; then
    success "ISC DHCP Server ✓ RUNNING"
    DHCP_STATUS="${GREEN}RUNNING ✓${NC}"
else
    warn "DHCP belum aktif (normal jika $IFACE_LAN belum ada client)"
    warn "Manual: systemctl restart isc-dhcp-server"
    DHCP_STATUS="${YELLOW}STANDBY ⚠${NC}"
fi

# ══════════════════════════════════════════════
# STEP 17 : LAPORAN AKHIR
# ══════════════════════════════════════════════
step "STEP 17 ► Laporan Akhir & Verifikasi"
slow_msg "Mengumpulkan semua informasi"
sleep 0.5

# Versi
SSH_VER=$(sshd -V 2>&1 | grep -oP 'OpenSSH_[\d.p]+' | head -1)
DHCP_VER=$(dhcpd --version 2>&1 | grep -oP 'isc-dhcp-[\d.]+' | head -1)

# IP aktif
ACTIVE_IP=$(ip addr show "$IFACE_LAN" 2>/dev/null | grep "inet " | awk '{print $2}' | head -1)

echo ""
echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║           LAPORAN INSTALASI LENGKAP                      ║${NC}"
echo -e "${BOLD}${BLUE}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${BLUE}║${NC} ${WHITE}[OS & VERSI]${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Distro        : ${GREEN}$DISTRO_NAME${NC}"
echo -e "${BOLD}${BLUE}║${NC}   OpenSSH Ver   : ${GREEN}${SSH_VER:-openssh-server}${NC}"
echo -e "${BOLD}${BLUE}║${NC}   DHCP Ver      : ${GREEN}${DHCP_VER:-isc-dhcp-server}${NC}"
echo -e "${BOLD}${BLUE}║${NC}"
echo -e "${BOLD}${BLUE}║${NC} ${WHITE}[STATUS SERVICE]${NC}"
echo -e "${BOLD}${BLUE}║${NC}   OpenSSH Server : $(eval echo -e $SSH_STATUS)"
echo -e "${BOLD}${BLUE}║${NC}   ISC DHCP Server: $(eval echo -e $DHCP_STATUS)"
echo -e "${BOLD}${BLUE}║${NC}"
echo -e "${BOLD}${BLUE}║${NC} ${WHITE}[NETWORK]${NC}"
echo -e "${BOLD}${BLUE}║${NC}   LAN Interface : ${GREEN}$IFACE_LAN${NC} (Host-Only - Adapter 1)"
echo -e "${BOLD}${BLUE}║${NC}   WAN Interface : ${GREEN}$IFACE_WAN${NC} (NAT        - Adapter 2)"
echo -e "${BOLD}${BLUE}║${NC}   Server IP     : ${YELLOW}$SERVER_IP${NC}"
echo -e "${BOLD}${BLUE}║${NC}   IP Aktif      : ${CYAN}${ACTIVE_IP:-Belum terpasang}${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Netmask       : ${GREEN}$SUBNET_MASK${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Broadcast     : ${GREEN}$BROADCAST${NC}"
echo -e "${BOLD}${BLUE}║${NC}"
echo -e "${BOLD}${BLUE}║${NC} ${WHITE}[DHCP POOL]${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Range         : ${GREEN}$RANGE_START${NC} s/d ${GREEN}$RANGE_END${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Total Host    : ${GREEN}50 Host${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Gateway DHCP  : ${GREEN}$SERVER_IP${NC}"
echo -e "${BOLD}${BLUE}║${NC}   DNS           : ${GREEN}$DNS_PRIMARY, $DNS_SECONDARY${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Lease         : ${GREEN}600s / max 7200s${NC}"
echo -e "${BOLD}${BLUE}║${NC}"
echo -e "${BOLD}${BLUE}║${NC} ${WHITE}[KONEKSI SSH - PuTTY / CMD]${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Host/IP  : ${YELLOW}$SERVER_IP${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Port     : ${YELLOW}22${NC}"
echo -e "${BOLD}${BLUE}║${NC}   User     : ${YELLOW}root${NC}"
echo -e "${BOLD}${BLUE}║${NC}   CMD/PS   : ${CYAN}ssh root@$SERVER_IP${NC}"
echo -e "${BOLD}${BLUE}║${NC}   PuTTY    : ${CYAN}Host=$SERVER_IP | Port=22 | SSH${NC}"
echo -e "${BOLD}${BLUE}║${NC}"
echo -e "${BOLD}${BLUE}║${NC} ${WHITE}[FILE PENTING]${NC}"
echo -e "${BOLD}${BLUE}║${NC}   IP Saved : ${CYAN}$IP_SAVE_FILE${NC}"
echo -e "${BOLD}${BLUE}║${NC}   SSH Conf : ${CYAN}/etc/ssh/sshd_config${NC}"
echo -e "${BOLD}${BLUE}║${NC}   DHCP Conf: ${CYAN}/etc/dhcp/dhcpd.conf${NC}"
echo -e "${BOLD}${BLUE}║${NC}   APT Log  : ${CYAN}$APT_LOG${NC}"
echo -e "${BOLD}${BLUE}║${NC}"
echo -e "${BOLD}${BLUE}║${NC} ${WHITE}[COMMAND CEK MANUAL]${NC}"
echo -e "${BOLD}${BLUE}║${NC}   ${CYAN}systemctl status ssh${NC}"
echo -e "${BOLD}${BLUE}║${NC}   ${CYAN}systemctl status isc-dhcp-server${NC}"
echo -e "${BOLD}${BLUE}║${NC}   ${CYAN}ip addr show $IFACE_LAN${NC}"
echo -e "${BOLD}${BLUE}║${NC}   ${CYAN}cat /var/lib/dhcp/dhcpd.leases${NC}"
echo -e "${BOLD}${BLUE}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${BLUE}║${NC} ${GREEN}✓ SELESAI! Disarankan reboot: ${CYAN}reboot${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Simpan Log ──
LOG_FILE="/root/aio_install_$(date +%Y%m%d_%H%M%S).log"
{
    echo "=== AIO Install Log ==="
    echo "Tanggal    : $(date)"
    echo "OS         : $DISTRO_NAME"
    echo "Server IP  : $SERVER_IP"
    echo "DHCP Range : $RANGE_START - $RANGE_END"
    echo "LAN IF     : $IFACE_LAN"
    echo "WAN IF     : $IFACE_WAN"
    echo "SSH Status : $(pgrep -x sshd > /dev/null 2>&1 && echo RUNNING || echo STOPPED)"
    echo "DHCP Status: $(pgrep -x dhcpd > /dev/null 2>&1 && echo RUNNING || echo STOPPED)"
} > "$LOG_FILE"

echo -e "  ${CYAN}[i] Log tersimpan di: $LOG_FILE${NC}"
echo ""
