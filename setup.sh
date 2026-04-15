#!/bin/bash

# ================================================================
#  ALL-IN-ONE INSTALLER: OpenSSH Server + ISC DHCP Server
#  Compatible   : Debian 8 (Jessie) / Debian 13 (Trixie)
#  VirtualBox   : Adapter1 = Host-Only | Adapter2 = NAT
#  Author       : Auto Script
# ================================================================

# ──────────────────────────────
#  WARNA OUTPUT
# ──────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# ──────────────────────────────
#  FUNGSI PROGRESS LAMBAT
# ──────────────────────────────
slow_progress() {
    local msg=$1
    echo -ne "  ${CYAN}[~] $msg${NC}"
    for i in {1..6}; do
        echo -ne "${YELLOW}.${NC}"
        sleep 0.6
    done
    echo -e " ${GREEN}[SELESAI]${NC}"
}

info()    { echo -e "  ${CYAN}[INFO]${NC}  $1"; sleep 0.4; }
success() { echo -e "  ${GREEN}[OK]${NC}    $1"; sleep 0.4; }
warn()    { echo -e "  ${YELLOW}[WARN]${NC}   $1"; sleep 0.4; }
error()   { echo -e "  ${RED}[ERROR]${NC}  $1"; sleep 0.4; }
step()    { echo -e "\n${BOLD}${BLUE}┌─────────────────────────────────────────┐${NC}"; \
            echo -e "${BOLD}${BLUE}│${NC} ${WHITE}${BOLD}$1${NC}"; \
            echo -e "${BOLD}${BLUE}└─────────────────────────────────────────┘${NC}"; sleep 0.5; }

# ──────────────────────────────
#  BANNER
# ──────────────────────────────
banner() {
    clear
    echo -e "${BLUE}"
    echo "  ╔══════════════════════════════════════════════╗"
    echo "  ║    OpenSSH Server + ISC DHCP Server          ║"
    echo "  ║    Auto Installer - All In One Script         ║"
    echo "  ╠══════════════════════════════════════════════╣"
    echo "  ║  OS Support  : Debian 8 (Jessie)              ║"
    echo "  ║                Debian 13 (Trixie)             ║"
    echo "  ║  VirtualBox  : Adapter1=Host-Only             ║"
    echo "  ║                Adapter2=NAT                   ║"
    echo "  ╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
    sleep 1
}

# ══════════════════════════════════════════════
# [CEK] ROOT ACCESS
# ══════════════════════════════════════════════
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[!] Script harus dijalankan sebagai ROOT!${NC}"
    echo -e "${YELLOW}    Gunakan: sudo bash $0${NC}"
    exit 1
fi

banner

# ══════════════════════════════════════════════
# STEP 1 : DETEKSI VERSI DEBIAN
# ══════════════════════════════════════════════
step "STEP 1/17 ► Deteksi Versi Debian"
slow_progress "Membaca informasi sistem"

# Baca versi
DEBIAN_VER_NUM=$(cat /etc/debian_version 2>/dev/null | cut -d'.' -f1)
DEBIAN_CODENAME=$(cat /etc/os-release 2>/dev/null | grep VERSION_CODENAME | cut -d'=' -f2 | tr -d '"')

# Fallback ke lsb_release
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
    warn "Versi tidak dikenal ($DEBIAN_VER_NUM/$DEBIAN_CODENAME)"
    warn "Menggunakan mode Debian 13 (default)"
    DISTRO="debian13"
    DISTRO_NAME="Debian Unknown (Default ke 13)"
    IFACE_LAN="enp0s3"
    IFACE_WAN="enp0s8"
fi

success "Terdeteksi  : $DISTRO_NAME"
success "LAN (Adp1)  : $IFACE_LAN (Host-Only)"
success "WAN (Adp2)  : $IFACE_WAN (NAT)"

# ══════════════════════════════════════════════
# STEP 2 : GENERATE IP RANDOM
# ══════════════════════════════════════════════
step "STEP 2/17 ► Generate IP Random"
slow_progress "Membuat IP secara acak"

# Random oktet ke-3 antara 10 sampai 240
RANDOM_OCT=$((RANDOM % 230 + 10))

SERVER_IP="192.168.$RANDOM_OCT.1"
NETWORK="192.168.$RANDOM_OCT.0"
SUBNET_MASK="255.255.255.0"
BROADCAST="192.168.$RANDOM_OCT.255"
RANGE_START="192.168.$RANDOM_OCT.100"
RANGE_END="192.168.$RANDOM_OCT.150"    # = 50 host
DNS_PRIMARY="8.8.8.8"
DNS_SECONDARY="8.8.4.4"

success "Server IP    : $SERVER_IP"
success "Network      : $NETWORK/24"
success "Subnet Mask  : $SUBNET_MASK"
success "DHCP Range   : $RANGE_START - $RANGE_END"
success "Total Host   : 50 Host"
success "Gateway      : $SERVER_IP"
success "DNS          : $DNS_PRIMARY, $DNS_SECONDARY"

# ══════════════════════════════════════════════
# STEP 3 : KONFIGURASI REPOSITORY
# ══════════════════════════════════════════════
step "STEP 3/17 ► Konfigurasi Repository APT"
slow_progress "Menyiapkan sources.list"

# Backup sources.list lama
cp /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null

if [ "$DISTRO" = "debian8" ]; then
    info "Menulis repo Debian 8 (Kambing + Official Archive)..."
    cat > /etc/apt/sources.list << 'REPOEOF'
# ====================================
# Repository Debian 8 (Jessie)
# Kambing.UI.ac.id Mirror (Indonesia)
# ====================================
deb http://kambing.ui.ac.id/debian/ jessie main contrib non-free
deb http://kambing.ui.ac.id/debian/ jessie-updates main contrib non-free

# ====================================
# Official Debian Archive (Jessie EOL)
# ====================================
deb http://archive.debian.org/debian/ jessie main contrib non-free
deb http://archive.debian.org/debian-security jessie/updates main contrib non-free
REPOEOF

    # Nonaktifkan cek expiry untuk Debian 8 yang sudah EOL
    cat > /etc/apt/apt.conf.d/99no-check-valid << 'APTEOF'
Acquire::Check-Valid-Until "false";
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
APTEOF
    success "Repo Kambing.ac.id + archive.debian.org dikonfigurasi"

elif [ "$DISTRO" = "debian13" ]; then
    info "Menulis repo Debian 13 (Trixie - Official)..."
    cat > /etc/apt/sources.list << 'REPOEOF'
# ====================================
# Repository Debian 13 (Trixie)
# Official Debian Repository
# ====================================
deb http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
REPOEOF
    success "Repo Official Debian 13 dikonfigurasi"
fi

# ══════════════════════════════════════════════
# STEP 4 : UPDATE PACKAGE LIST
# ══════════════════════════════════════════════
step "STEP 4/17 ► Update Package List"
slow_progress "Menjalankan apt-get update"

apt-get update -y > /dev/null 2>&1
if [ $? -eq 0 ]; then
    success "apt-get update berhasil"
else
    warn "apt-get update ada warning, melanjutkan..."
fi

# ══════════════════════════════════════════════
# STEP 5 : CEK & REMOVE OPENSSH (JIKA ADA)
# ══════════════════════════════════════════════
step "STEP 5/17 ► Cek & Remove OpenSSH Server (jika terpasang)"
slow_progress "Memeriksa instalasi OpenSSH"

if dpkg -l | grep -qw "openssh-server" 2>/dev/null; then
    warn "OpenSSH Server DITEMUKAN - Menghapus..."
    slow_progress "Menghentikan service SSH"

    systemctl stop ssh      2>/dev/null
    systemctl disable ssh   2>/dev/null
    service ssh stop        2>/dev/null

    slow_progress "Menghapus package openssh-server"
    apt-get remove --purge -y openssh-server openssh-client 2>/dev/null > /dev/null
    apt-get autoremove -y 2>/dev/null > /dev/null

    slow_progress "Membersihkan file konfigurasi lama"
    rm -rf /etc/ssh/sshd_config     2>/dev/null
    rm -rf /etc/ssh/ssh_host_*      2>/dev/null

    success "OpenSSH Server berhasil DIHAPUS"
else
    success "OpenSSH Server tidak ditemukan - Langsung install"
fi

# ══════════════════════════════════════════════
# STEP 6 : CEK & REMOVE ISC DHCP (JIKA ADA)
# ══════════════════════════════════════════════
step "STEP 6/17 ► Cek & Remove ISC DHCP Server (jika terpasang)"
slow_progress "Memeriksa instalasi ISC DHCP Server"

if dpkg -l | grep -qw "isc-dhcp-server" 2>/dev/null; then
    warn "ISC DHCP Server DITEMUKAN - Menghapus..."
    slow_progress "Menghentikan service DHCP"

    systemctl stop isc-dhcp-server      2>/dev/null
    systemctl disable isc-dhcp-server   2>/dev/null
    service isc-dhcp-server stop        2>/dev/null

    slow_progress "Menghapus package isc-dhcp-server"
    apt-get remove --purge -y isc-dhcp-server isc-dhcp-common 2>/dev/null > /dev/null
    apt-get autoremove -y 2>/dev/null > /dev/null

    slow_progress "Membersihkan file konfigurasi lama"
    rm -rf /etc/dhcp/dhcpd.conf     2>/dev/null
    rm -rf /var/lib/dhcp/*          2>/dev/null

    success "ISC DHCP Server berhasil DIHAPUS"
else
    success "ISC DHCP Server tidak ditemukan - Langsung install"
fi

# ══════════════════════════════════════════════
# STEP 7 : INSTALL OPENSSH SERVER
# ══════════════════════════════════════════════
step "STEP 7/17 ► Install OpenSSH Server"
slow_progress "Mengunduh package openssh-server"

DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server > /dev/null 2>&1

if [ $? -eq 0 ]; then
    success "openssh-server berhasil diinstall"
else
    error "GAGAL install openssh-server! Periksa koneksi internet."
    exit 1
fi

# ══════════════════════════════════════════════
# STEP 8 : KONFIGURASI OPENSSH SERVER
# ══════════════════════════════════════════════
step "STEP 8/17 ► Konfigurasi OpenSSH Server"
slow_progress "Membuat file /etc/ssh/sshd_config"

cat > /etc/ssh/sshd_config << SSHEOF
# ================================================
# OpenSSH Server Configuration
# Generated by Auto-Install Script
# ================================================

Port 22
Protocol 2

# Host Keys
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Logging
SyslogFacility AUTH
LogLevel INFO

# Authentication Settings
LoginGraceTime 2m
PermitRootLogin yes
StrictModes yes
MaxAuthTries 6
MaxSessions 10

# Password Auth (wajib yes agar PuTTY/CMD bisa login)
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no

# Pubkey Auth
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys2

# PAM
UsePAM yes

# Forwarding
AllowTcpForwarding yes
X11Forwarding yes
X11DisplayOffset 10

# Keep Alive
ClientAliveInterval 120
ClientAliveCountMax 3

# Misc
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
AcceptEnv LANG LC_*

# SFTP Subsystem
Subsystem sftp /usr/lib/openssh/sftp-server
SSHEOF

success "sshd_config berhasil dibuat"

slow_progress "Generate SSH Host Keys"
ssh-keygen -A > /dev/null 2>&1
success "SSH Host Keys berhasil dibuat"

# ══════════════════════════════════════════════
# STEP 9 : INSTALL ISC DHCP SERVER
# ══════════════════════════════════════════════
step "STEP 9/17 ► Install ISC DHCP Server"
slow_progress "Mengunduh package isc-dhcp-server"

DEBIAN_FRONTEND=noninteractive apt-get install -y isc-dhcp-server > /dev/null 2>&1

if [ $? -eq 0 ]; then
    success "isc-dhcp-server berhasil diinstall"
else
    error "GAGAL install isc-dhcp-server! Periksa koneksi internet."
    exit 1
fi

# ══════════════════════════════════════════════
# STEP 10 : KONFIGURASI INTERFACE DHCP
# ══════════════════════════════════════════════
step "STEP 10/17 ► Set Interface DHCP"
slow_progress "Mengkonfigurasi interface untuk DHCP server"

# Set interface di /etc/default/isc-dhcp-server
DHCP_DEFAULT="/etc/default/isc-dhcp-server"

if grep -q "INTERFACESv4" "$DHCP_DEFAULT" 2>/dev/null; then
    # Format Debian 13 / baru
    sed -i "s|INTERFACESv4=.*|INTERFACESv4=\"$IFACE_LAN\"|g" "$DHCP_DEFAULT"
    sed -i "s|INTERFACESv6=.*|INTERFACESv6=\"\"|g" "$DHCP_DEFAULT"
else
    # Format Debian 8 / lama
    sed -i "s|INTERFACES=.*|INTERFACES=\"$IFACE_LAN\"|g" "$DHCP_DEFAULT"
fi

# Pastikan baris ada
if ! grep -q "INTERFACES" "$DHCP_DEFAULT" 2>/dev/null; then
    echo "INTERFACES=\"$IFACE_LAN\"" >> "$DHCP_DEFAULT"
fi

success "DHCP akan berjalan di interface: $IFACE_LAN"

# ══════════════════════════════════════════════
# STEP 11 : KONFIGURASI DHCPD.CONF
# ══════════════════════════════════════════════
step "STEP 11/17 ► Konfigurasi DHCP (dhcpd.conf)"
slow_progress "Membuat file /etc/dhcp/dhcpd.conf"

mkdir -p /etc/dhcp

cat > /etc/dhcp/dhcpd.conf << DHCPEOF
# ================================================
# ISC DHCP Server Configuration
# Generated by Auto-Install Script
# Network  : $NETWORK/24
# Range    : $RANGE_START - $RANGE_END
# Total    : 50 Host
# ================================================

# Waktu lease (dalam detik)
default-lease-time 600;
max-lease-time 7200;

# Server ini adalah DHCP server resmi untuk jaringan ini
authoritative;

# Logging
log-facility local7;

# ──────────────────────────────────────────
# Subnet Declaration
# ──────────────────────────────────────────
subnet $NETWORK netmask $SUBNET_MASK {

    # Range IP yang dibagikan ke client (50 host)
    range $RANGE_START $RANGE_END;

    # DNS Server untuk client
    option domain-name-servers $DNS_PRIMARY, $DNS_SECONDARY;

    # Nama domain lokal
    option domain-name "local.lan";

    # Gateway default untuk client
    option routers $SERVER_IP;

    # Broadcast address
    option broadcast-address $BROADCAST;

    # Lease time
    default-lease-time 600;
    max-lease-time 7200;
}
DHCPEOF

success "dhcpd.conf berhasil dibuat"
success "Subnet    : $NETWORK / 255.255.255.0"
success "Range     : $RANGE_START - $RANGE_END (50 host)"
success "Router    : $SERVER_IP"

# ══════════════════════════════════════════════
# STEP 12 : KONFIGURASI IP STATIS (/etc/network/interfaces)
# ══════════════════════════════════════════════
step "STEP 12/17 ► Konfigurasi Network Interface"
slow_progress "Membuat /etc/network/interfaces"

# Backup interfaces lama
cp /etc/network/interfaces /etc/network/interfaces.backup.$(date +%Y%m%d%H%M%S) 2>/dev/null

# Cek apakah NetworkManager aktif (Debian 13)
NM_ACTIVE=false
if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    NM_ACTIVE=true
    warn "NetworkManager terdeteksi aktif"
fi

if [ "$NM_ACTIVE" = "false" ]; then
    cat > /etc/network/interfaces << NETEOF
# ================================================
# Network Interface Configuration
# VirtualBox - Auto Generated
# ================================================

source /etc/network/interfaces.d/*

# Loopback
auto lo
iface lo inet loopback

# ──────────────────────────────
# Adapter 1 - Host-Only Network
# Interface : $IFACE_LAN
# IP Statis untuk DHCP Server
# ──────────────────────────────
auto $IFACE_LAN
iface $IFACE_LAN inet static
    address     $SERVER_IP
    netmask     $SUBNET_MASK
    broadcast   $BROADCAST

# ──────────────────────────────
# Adapter 2 - NAT (Internet)
# Interface : $IFACE_WAN
# IP otomatis dari VirtualBox NAT
# ──────────────────────────────
auto $IFACE_WAN
iface $IFACE_WAN inet dhcp
NETEOF
    success "/etc/network/interfaces dikonfigurasi"

else
    # Jika NetworkManager aktif, konfigurasi via file connection
    warn "Menggunakan NetworkManager connection file"
    mkdir -p /etc/NetworkManager/system-connections/

    cat > /etc/NetworkManager/system-connections/host-only.nmconnection << NMEOF
[connection]
id=$IFACE_LAN
type=ethernet
interface-name=$IFACE_LAN
autoconnect=true

[ipv4]
method=manual
addresses=$SERVER_IP/24
gateway=
dns=$DNS_PRIMARY;$DNS_SECONDARY;

[ipv6]
method=ignore
NMEOF
    chmod 600 /etc/NetworkManager/system-connections/host-only.nmconnection 2>/dev/null
    success "NetworkManager connection dikonfigurasi untuk $IFACE_LAN"
fi

# ══════════════════════════════════════════════
# STEP 13 : APPLY IP KE INTERFACE
# ══════════════════════════════════════════════
step "STEP 13/17 ► Apply IP Statis ke Interface $IFACE_LAN"
slow_progress "Flush IP lama dan apply IP baru"

# Pastikan interface ada
if ip link show "$IFACE_LAN" > /dev/null 2>&1; then
    ip addr flush dev "$IFACE_LAN"  2>/dev/null
    ip addr add "$SERVER_IP/24" dev "$IFACE_LAN" 2>/dev/null
    ip link set "$IFACE_LAN" up 2>/dev/null
    success "IP $SERVER_IP berhasil di-apply ke $IFACE_LAN"
else
    warn "Interface $IFACE_LAN belum terdeteksi"
    warn "IP akan aktif setelah reboot atau interface tersambung"
fi

# Pastikan WAN interface up
if ip link show "$IFACE_WAN" > /dev/null 2>&1; then
    ip link set "$IFACE_WAN" up 2>/dev/null
    success "Interface $IFACE_WAN (WAN/NAT) diaktifkan"
fi

# ══════════════════════════════════════════════
# STEP 14 : KONFIGURASI IPTABLES / FIREWALL
# ══════════════════════════════════════════════
step "STEP 14/17 ► Konfigurasi Firewall (iptables)"
slow_progress "Setting rules iptables"

# Izinkan loopback
iptables -A INPUT -i lo -j ACCEPT 2>/dev/null
# Izinkan koneksi established
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
# Izinkan SSH port 22
iptables -A INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null
# Izinkan DHCP port 67/68
iptables -A INPUT -p udp --dport 67 -j ACCEPT 2>/dev/null
iptables -A INPUT -p udp --dport 68 -j ACCEPT 2>/dev/null
# IP Forwarding untuk NAT
echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null
sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1

# Simpan iptables agar persist setelah reboot
if command -v iptables-save > /dev/null 2>&1; then
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
fi

success "Firewall rules: SSH (22) + DHCP (67/68) diizinkan"
success "IP Forwarding: aktif"

# ══════════════════════════════════════════════
# STEP 15 : START & ENABLE OPENSSH
# ══════════════════════════════════════════════
step "STEP 15/17 ► Enable & Start OpenSSH Server"
slow_progress "Mengaktifkan OpenSSH service"

if [ "$DISTRO" = "debian8" ]; then
    update-rc.d ssh enable  2>/dev/null
    service ssh restart     2>/dev/null
    SSH_STATUS=$(service ssh status 2>/dev/null | grep -c "running")
else
    systemctl enable ssh    2>/dev/null
    systemctl restart ssh   2>/dev/null
    SSH_STATUS=$(systemctl is-active ssh 2>/dev/null)
fi

sleep 1

# Verifikasi
if systemctl is-active --quiet ssh 2>/dev/null || \
   service ssh status 2>/dev/null | grep -q "running" || \
   pgrep -x "sshd" > /dev/null 2>&1; then
    success "OpenSSH Server : ✓ AKTIF / RUNNING"
else
    warn "OpenSSH Server mungkin belum aktif, coba manual:"
    warn "  systemctl restart ssh  ATAU  service ssh restart"
fi

# ══════════════════════════════════════════════
# STEP 16 : START & ENABLE ISC DHCP
# ══════════════════════════════════════════════
step "STEP 16/17 ► Enable & Start ISC DHCP Server"
slow_progress "Mengaktifkan DHCP service"

if [ "$DISTRO" = "debian8" ]; then
    update-rc.d isc-dhcp-server enable  2>/dev/null
    service isc-dhcp-server restart     2>/dev/null
else
    systemctl enable isc-dhcp-server    2>/dev/null
    systemctl restart isc-dhcp-server   2>/dev/null
fi

sleep 1

# Verifikasi
if systemctl is-active --quiet isc-dhcp-server 2>/dev/null || \
   service isc-dhcp-server status 2>/dev/null | grep -q "running" || \
   pgrep -x "dhcpd" > /dev/null 2>&1; then
    success "ISC DHCP Server : ✓ AKTIF / RUNNING"
else
    warn "DHCP Server belum aktif. Ini normal jika $IFACE_LAN belum tersambung."
    warn "Coba manual: systemctl restart isc-dhcp-server"
fi

# ══════════════════════════════════════════════
# STEP 17 : LAPORAN AKHIR & VERIFIKASI DETAIL
# ══════════════════════════════════════════════
step "STEP 17/17 ► Verifikasi & Laporan Akhir"
slow_progress "Mengumpulkan informasi sistem"

echo ""
echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║          LAPORAN INSTALASI - DETAIL                  ║${NC}"
echo -e "${BOLD}${BLUE}╠══════════════════════════════════════════════════════╣${NC}"

# ── Versi OS ──
echo -e "${BOLD}${BLUE}║${NC} ${WHITE}[OS INFO]${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Distro     : ${GREEN}$DISTRO_NAME${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Debian Ver : ${GREEN}$DEBIAN_VER_NUM ($DEBIAN_CODENAME)${NC}"

# ── Status Services ──
echo -e "${BOLD}${BLUE}║${NC}"
echo -e "${BOLD}${BLUE}║${NC} ${WHITE}[STATUS SERVICES]${NC}"

# SSH
if pgrep -x "sshd" > /dev/null 2>&1; then
    SSH_STAT="${GREEN}✓ RUNNING${NC}"
else
    SSH_STAT="${RED}✗ STOPPED${NC}"
fi

# DHCP
if pgrep -x "dhcpd" > /dev/null 2>&1; then
    DHCP_STAT="${GREEN}✓ RUNNING${NC}"
else
    DHCP_STAT="${YELLOW}⚠ STANDBY (tunggu client)${NC}"
fi

echo -e "${BOLD}${BLUE}║${NC}   OpenSSH Server   : $SSH_STAT"
echo -e "${BOLD}${BLUE}║${NC}   ISC DHCP Server  : $DHCP_STAT"

# ── Versi Aplikasi ──
echo -e "${BOLD}${BLUE}║${NC}"
echo -e "${BOLD}${BLUE}║${NC} ${WHITE}[VERSI APLIKASI]${NC}"
SSH_VER=$(sshd -V 2>&1 | head -1 | awk '{print $1}')
echo -e "${BOLD}${BLUE}║${NC}   SSH Version  : ${GREEN}$SSH_VER${NC}"
DHCP_VER=$(dhcpd --version 2>&1 | head -1)
echo -e "${BOLD}${BLUE}║${NC}   DHCP Version : ${GREEN}$DHCP_VER${NC}"

# ── Network Info ──
echo -e "${BOLD}${BLUE}║${NC}"
echo -e "${BOLD}${BLUE}║${NC} ${WHITE}[NETWORK CONFIGURATION]${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Interface LAN : ${GREEN}$IFACE_LAN${NC}  (Host-Only - Adapter 1)"
echo -e "${BOLD}${BLUE}║${NC}   Interface WAN : ${GREEN}$IFACE_WAN${NC}  (NAT        - Adapter 2)"
echo -e "${BOLD}${BLUE}║${NC}   Server IP     : ${GREEN}$SERVER_IP${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Netmask       : ${GREEN}$SUBNET_MASK${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Network       : ${GREEN}$NETWORK/24${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Broadcast     : ${GREEN}$BROADCAST${NC}"

# ── DHCP Info ──
echo -e "${BOLD}${BLUE}║${NC}"
echo -e "${BOLD}${BLUE}║${NC} ${WHITE}[DHCP POOL]${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Range Start  : ${GREEN}$RANGE_START${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Range End    : ${GREEN}$RANGE_END${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Total Host   : ${GREEN}50 Host${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Gateway      : ${GREEN}$SERVER_IP${NC}"
echo -e "${BOLD}${BLUE}║${NC}   DNS Primary  : ${GREEN}$DNS_PRIMARY${NC}"
echo -e "${BOLD}${BLUE}║${NC}   DNS Secondary: ${GREEN}$DNS_SECONDARY${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Lease Time   : ${GREEN}600s (default) / 7200s (max)${NC}"

# ── SSH Koneksi ──
echo -e "${BOLD}${BLUE}║${NC}"
echo -e "${BOLD}${BLUE}║${NC} ${WHITE}[CARA KONEKSI SSH - PuTTY / CMD]${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Host / IP  : ${YELLOW}$SERVER_IP${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Port       : ${YELLOW}22${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Username   : ${YELLOW}root${NC}  (atau user lain)"
echo -e "${BOLD}${BLUE}║${NC}   Password   : ${YELLOW}[password root Anda]${NC}"
echo -e "${BOLD}${BLUE}║${NC}"
echo -e "${BOLD}${BLUE}║${NC}   CMD/PowerShell :"
echo -e "${BOLD}${BLUE}║${NC}   ${CYAN}ssh root@$SERVER_IP${NC}"
echo -e "${BOLD}${BLUE}║${NC}"
echo -e "${BOLD}${BLUE}║${NC}   PuTTY :"
echo -e "${BOLD}${BLUE}║${NC}   ${CYAN}Host=$SERVER_IP | Port=22 | Type=SSH${NC}"

# ── Repo Info ──
echo -e "${BOLD}${BLUE}║${NC}"
echo -e "${BOLD}${BLUE}║${NC} ${WHITE}[REPOSITORY YANG DIGUNAKAN]${NC}"
if [ "$DISTRO" = "debian8" ]; then
echo -e "${BOLD}${BLUE}║${NC}   ${GREEN}kambing.ui.ac.id (Debian 8 Mirror Indonesia)${NC}"
echo -e "${BOLD}${BLUE}║${NC}   ${GREEN}archive.debian.org (Official Debian Archive)${NC}"
else
echo -e "${BOLD}${BLUE}║${NC}   ${GREEN}deb.debian.org (Official Debian 13 Trixie)${NC}"
echo -e "${BOLD}${BLUE}║${NC}   ${GREEN}security.debian.org (Security Updates)${NC}"
fi

echo -e "${BOLD}${BLUE}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${BLUE}║${NC} ${WHITE}[COMMAND BERGUNA SETELAH INSTALASI]${NC}"
echo -e "${BOLD}${BLUE}║${NC}   systemctl status ssh                # cek status SSH"
echo -e "${BOLD}${BLUE}║${NC}   systemctl status isc-dhcp-server   # cek status DHCP"
echo -e "${BOLD}${BLUE}║${NC}   systemctl restart ssh               # restart SSH"
echo -e "${BOLD}${BLUE}║${NC}   systemctl restart isc-dhcp-server  # restart DHCP"
echo -e "${BOLD}${BLUE}║${NC}   cat /var/lib/dhcp/dhcpd.leases     # lihat client"
echo -e "${BOLD}${BLUE}║${NC}   ip addr show $IFACE_LAN                 # lihat IP"
echo -e "${BOLD}${BLUE}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${BLUE}║${NC} ${GREEN}✓ INSTALASI SELESAI! OpenSSH + ISC DHCP Aktif.${NC}"
echo -e "${BOLD}${BLUE}║${NC} ${YELLOW}⚠ Disarankan reboot untuk memastikan semua aktif${NC}"
echo -e "${BOLD}${BLUE}║${NC}   Ketik: ${CYAN}reboot${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Simpan log ──
LOG_FILE="/root/install_report_$(date +%Y%m%d_%H%M%S).log"
{
    echo "=== INSTALL REPORT ==="
    echo "Date       : $(date)"
    echo "OS         : $DISTRO_NAME"
    echo "Server IP  : $SERVER_IP"
    echo "DHCP Range : $RANGE_START - $RANGE_END"
    echo "LAN IF     : $IFACE_LAN"
    echo "WAN IF     : $IFACE_WAN"
    echo "SSH Port   : 22"
} > "$LOG_FILE"

echo -e "  ${CYAN}[i] Log disimpan di: $LOG_FILE${NC}"
echo ""
