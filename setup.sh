#!/bin/bash
# ============================================================
#  AUTHOR    : ADAM SANJAYA XI TJKT 2
#  PROJECT   : OpenSSH + ISC-DHCP Server — FULL FRESH SETUP
#  TARGET    : Debian 13 (Trixie) — VirtualBox
#  INTERFACE : enp0s3
#  DHCP RANGE: 192.168.1.50 – 192.168.1.100
#  NOTE      : Wipes everything first, then builds from zero
# ============================================================

# ── Must run as root ─────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Run as root: sudo bash setup_adam.sh"
  exit 1
fi

# ── Colors ───────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "\n${CYAN}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERR]${NC}   $1"; exit 1; }
banner()  { echo -e "\n${YELLOW}════════════════════════════════════════${NC}\n  $1\n${YELLOW}════════════════════════════════════════${NC}"; }

# ── Config variables ─────────────────────────────────────────
IFACE="enp0s3"
SERVER_IP="192.168.1.1"
SUBNET="192.168.1.0"
NETMASK="255.255.255.0"
PREFIX="24"
BROADCAST="192.168.1.255"
RANGE_START="192.168.1.50"
RANGE_END="192.168.1.100"
DNS1="8.8.8.8"
DNS2="8.8.4.4"
DEFAULT_LEASE="3600"
MIN_LEASE="600"
MAX_LEASE="7200"

clear
echo ""
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║       ADAM SANJAYA XI TJKT 2 — FRESH SETUP          ║"
echo "  ║       OpenSSH + ISC-DHCP | Debian 13 | VirtualBox   ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo ""
echo "  This script will:"
echo "  1. Wipe ALL previous SSH and DHCP installs/configs"
echo "  2. Fix apt sources (remove cdrom, add online mirrors)"
echo "  3. Install everything fresh from zero"
echo "  4. Apply static IP, configure DHCP + SSH, start services"
echo ""
read -rp "  Press ENTER to begin or Ctrl+C to cancel..." _

# ════════════════════════════════════════════════════════════
#  PHASE 1 — WIPE EVERYTHING
# ════════════════════════════════════════════════════════════
banner "PHASE 1 — WIPING PREVIOUS INSTALLS"

# ── Stop services if running ─────────────────────────────────
info "Stopping existing services..."
systemctl stop isc-dhcp-server 2>/dev/null && warn "Stopped: isc-dhcp-server" || true
systemctl stop ssh             2>/dev/null && warn "Stopped: ssh"             || true
systemctl stop sshd            2>/dev/null || true

# ── Purge packages completely ────────────────────────────────
info "Purging openssh-server, isc-dhcp-server, ifupdown..."
apt-get purge -y openssh-server isc-dhcp-server isc-dhcp-common ifupdown 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
success "Packages purged."

# ── Delete all config files ──────────────────────────────────
info "Removing all leftover config files..."

# SSH
rm -rf /etc/ssh/sshd_config
rm -rf /etc/ssh/sshd_config.bak*
rm -rf /etc/ssh/sshd_config.original*
rm -rf /etc/motd

# DHCP
rm -rf /etc/dhcp/dhcpd.conf
rm -rf /etc/dhcp/dhcpd.conf.bak*
rm -rf /etc/default/isc-dhcp-server
rm -rf /var/lib/dhcp/dhcpd.leases
rm -rf /var/lib/dhcp/dhcpd.leases~
mkdir -p /var/lib/dhcp
touch /var/lib/dhcp/dhcpd.leases    # recreate empty leases file

# Network interfaces — remove enp0s3 block
info "Cleaning /etc/network/interfaces..."
IFACES_FILE="/etc/network/interfaces"
# Rebuild the file keeping only loopback
cat > "$IFACES_FILE" <<'EOF'
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback
EOF
success "interfaces file reset to loopback only."

# Remove any .bak files from previous runs
rm -f /etc/apt/sources.list.original.bak* /etc/apt/sources.list.bak* 2>/dev/null
success "All old configs deleted."

# ── Flush any IP on enp0s3 left from before ──────────────────
info "Flushing any existing IP on $IFACE..."
ip addr flush dev "$IFACE" 2>/dev/null || true
ip link set "$IFACE" down 2>/dev/null || true
success "$IFACE flushed."

# ════════════════════════════════════════════════════════════
#  PHASE 2 — FIX APT SOURCES
# ════════════════════════════════════════════════════════════
banner "PHASE 2 — FIXING APT SOURCES"

SOURCES="/etc/apt/sources.list"

# ── Remove every cdrom line ───────────────────────────────────
info "Nuking all cdrom entries..."
grep -vi "cdrom" "$SOURCES" > /tmp/sources.clean 2>/dev/null || true
mv /tmp/sources.clean "$SOURCES"
success "cdrom lines removed."

# ── Disable all files in sources.list.d ──────────────────────
info "Disabling all /etc/apt/sources.list.d/*.list files..."
for f in /etc/apt/sources.list.d/*.list; do
  [[ -f "$f" ]] && mv "$f" "${f}.disabled" && warn "Disabled: $f"
done
success "sources.list.d cleaned."

# ── Write clean Debian 13 Trixie mirrors ─────────────────────
info "Writing clean Debian 13 (Trixie) mirror list..."
cat > "$SOURCES" <<'EOF'
# /etc/apt/sources.list
# ADAM SANJAYA XI TJKT 2 — Debian 13 Trixie — Clean mirrors

deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
EOF
success "Clean sources.list written."

# ════════════════════════════════════════════════════════════
#  PHASE 3 — GET INTERNET ACCESS (temporary DHCP on enp0s3)
# ════════════════════════════════════════════════════════════
banner "PHASE 3 — CONNECTING TO INTERNET"

info "Bringing up $IFACE temporarily via DHCP..."
ip link set "$IFACE" up
sleep 1
dhclient "$IFACE" 2>/dev/null || true
sleep 2

if ping -c 2 -W 3 8.8.8.8 &>/dev/null; then
  success "Internet is reachable via $IFACE."
else
  warn "Cannot ping 8.8.8.8."
  warn "Make sure VirtualBox adapter is set to NAT before continuing."
  warn "Trying apt-get update anyway..."
fi

# ════════════════════════════════════════════════════════════
#  PHASE 4 — UPDATE AND INSTALL PACKAGES
# ════════════════════════════════════════════════════════════
banner "PHASE 4 — INSTALLING PACKAGES"

info "Running apt-get update..."
apt-get update -y || error "apt-get update failed.\n  → Make sure VirtualBox adapter = NAT (needs internet)."
success "Package list updated."

info "Installing: openssh-server isc-dhcp-server net-tools ifupdown..."
apt-get install -y openssh-server isc-dhcp-server net-tools ifupdown || \
  error "Package install failed."
success "All packages installed fresh."

# ════════════════════════════════════════════════════════════
#  PHASE 5 — APPLY STATIC IP (before DHCP server starts)
# ════════════════════════════════════════════════════════════
banner "PHASE 5 — APPLYING STATIC IP"

info "Releasing DHCP lease on $IFACE..."
dhclient -r "$IFACE" 2>/dev/null || true
sleep 1

info "Flushing $IFACE and setting static IP $SERVER_IP..."
ip addr flush dev "$IFACE"
ip addr add "$SERVER_IP/$PREFIX" broadcast "$BROADCAST" dev "$IFACE"
ip link set "$IFACE" up
sleep 1

# Confirm it's actually assigned
if ip addr show "$IFACE" | grep -q "inet $SERVER_IP"; then
  success "Static IP $SERVER_IP/$PREFIX is live on $IFACE."
else
  error "Failed to assign $SERVER_IP to $IFACE.\n  Run 'ip a' to check your interface name."
fi

# ── Write to /etc/network/interfaces for persistence ─────────
info "Writing static IP to /etc/network/interfaces..."
cat >> "$IFACES_FILE" <<EOF

# enp0s3 — ADAM SANJAYA XI TJKT 2 — Static IP for DHCP Server
auto $IFACE
iface $IFACE inet static
    address   $SERVER_IP
    netmask   $NETMASK
    broadcast $BROADCAST
EOF
success "Static IP persisted to /etc/network/interfaces."

# ════════════════════════════════════════════════════════════
#  PHASE 6 — CONFIGURE ISC-DHCP-SERVER
# ════════════════════════════════════════════════════════════
banner "PHASE 6 — CONFIGURING DHCP SERVER"

info "Writing /etc/dhcp/dhcpd.conf..."
cat > /etc/dhcp/dhcpd.conf <<EOF
# ============================================================
#  dhcpd.conf
#  Author    : ADAM SANJAYA XI TJKT 2
#  Server IP : $SERVER_IP
#  Interface : $IFACE
#  Range     : $RANGE_START – $RANGE_END (51 hosts)
# ============================================================

authoritative;
log-facility local7;

# ── Lease timing ─────────────────────────────────────────────
default-lease-time  $DEFAULT_LEASE;   # 1 hour
min-lease-time      $MIN_LEASE;       # 10 minutes
max-lease-time      $MAX_LEASE;       # 2 hours

# ── Subnet declaration ───────────────────────────────────────
subnet $SUBNET netmask $NETMASK {

    range                       $RANGE_START $RANGE_END;

    option routers              $SERVER_IP;
    option subnet-mask          $NETMASK;
    option broadcast-address    $BROADCAST;
    option domain-name-servers  $DNS1, $DNS2;
    option domain-name          "adamsanjaya.local";

    default-lease-time          $DEFAULT_LEASE;
    min-lease-time              $MIN_LEASE;
    max-lease-time              $MAX_LEASE;
}
EOF
success "dhcpd.conf written."

info "Binding isc-dhcp-server to $IFACE..."
cat > /etc/default/isc-dhcp-server <<EOF
# ADAM SANJAYA XI TJKT 2
INTERFACESv4="$IFACE"
INTERFACESv6=""
EOF
success "DHCP bound to $IFACE."

# ════════════════════════════════════════════════════════════
#  PHASE 7 — CONFIGURE OPENSSH
# ════════════════════════════════════════════════════════════
banner "PHASE 7 — CONFIGURING OPENSSH"

info "Writing fresh /etc/ssh/sshd_config..."
cat > /etc/ssh/sshd_config <<'EOF'
# ============================================================
#  sshd_config — ADAM SANJAYA XI TJKT 2
#  Debian 13 | VirtualBox | enp0s3
# ============================================================

Port 22
ListenAddress 0.0.0.0
AddressFamily inet

# Authentication
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
PermitEmptyPasswords no
AuthorizedKeysFile .ssh/authorized_keys

# Security
LoginGraceTime 60
MaxAuthTries 4
MaxSessions 20
StrictModes yes

# Features
X11Forwarding yes
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
UseDNS no

# Subsystem
Subsystem sftp /usr/lib/openssh/sftp-server
EOF
success "sshd_config written."

info "Writing login banner (MOTD)..."
cat > /etc/motd <<'EOF'

  ╔══════════════════════════════════════════════════════╗
  ║         ADAM SANJAYA — XI TJKT 2                     ║
  ║         Debian 13 Server | VirtualBox                ║
  ║         OpenSSH + ISC-DHCP Server                    ║
  ║                                                      ║
  ║   Unauthorized access is strictly prohibited.       ║
  ╚══════════════════════════════════════════════════════╝

EOF
success "MOTD written."

# ════════════════════════════════════════════════════════════
#  PHASE 8 — START SERVICES
# ════════════════════════════════════════════════════════════
banner "PHASE 8 — STARTING SERVICES"

# ── SSH ──────────────────────────────────────────────────────
info "Starting SSH..."
systemctl daemon-reexec
systemctl enable ssh
systemctl restart ssh
sleep 1
systemctl is-active --quiet ssh \
  && success "ssh             → RUNNING ✓" \
  || warn    "ssh             → FAILED  (run: systemctl status ssh)"

# ── Double-check static IP still applied before DHCP starts ──
info "Verifying static IP before starting DHCP..."
if ! ip addr show "$IFACE" | grep -q "inet $SERVER_IP"; then
  warn "IP was lost — re-applying $SERVER_IP..."
  ip addr add "$SERVER_IP/$PREFIX" broadcast "$BROADCAST" dev "$IFACE"
  ip link set "$IFACE" up
  sleep 1
fi
success "IP $SERVER_IP confirmed on $IFACE."

# ── DHCP ─────────────────────────────────────────────────────
info "Starting isc-dhcp-server..."
systemctl enable isc-dhcp-server
systemctl restart isc-dhcp-server
sleep 2
systemctl is-active --quiet isc-dhcp-server \
  && success "isc-dhcp-server → RUNNING ✓" \
  || {
    warn "isc-dhcp-server → FAILED"
    warn "Showing last 10 log lines:"
    journalctl -u isc-dhcp-server --no-pager -n 10
  }

# ════════════════════════════════════════════════════════════
#  PHASE 9 — UFW FIREWALL (if present)
# ════════════════════════════════════════════════════════════
if command -v ufw &>/dev/null; then
  banner "PHASE 9 — FIREWALL RULES"
  ufw allow 22/tcp  comment "SSH  - ADAM SANJAYA"
  ufw allow 67/udp  comment "DHCP - ADAM SANJAYA"
  ufw allow 68/udp  comment "DHCP - ADAM SANJAYA"
  ufw --force enable
  success "UFW rules applied."
fi

# ════════════════════════════════════════════════════════════
#  DONE — SUMMARY
# ════════════════════════════════════════════════════════════
echo ""
echo "  ╔══════════════════════════════════════════════════════╗"
echo -e "  ║  ${GREEN}SETUP COMPLETE — ADAM SANJAYA XI TJKT 2${NC}             ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo ""
echo -e "  ${CYAN}Server IP      :${NC} $SERVER_IP"
echo -e "  ${CYAN}SSH Port       :${NC} 22"
echo -e "  ${CYAN}DHCP Range     :${NC} $RANGE_START – $RANGE_END  (51 hosts)"
echo -e "  ${CYAN}Lease Default  :${NC} 3600s  (1 hour)"
echo -e "  ${CYAN}Lease Min      :${NC} 600s   (10 minutes)"
echo -e "  ${CYAN}Lease Max      :${NC} 7200s  (2 hours)"
echo -e "  ${CYAN}Interface      :${NC} $IFACE"
echo -e "  ${CYAN}Domain         :${NC} adamsanjaya.local"
echo ""
echo -e "  ${YELLOW}PuTTY / CMD Connection:${NC}"
echo -e "    Host : $SERVER_IP"
echo -e "    Port : 22"
echo -e "    CMD  : ssh root@$SERVER_IP"
echo ""
echo -e "  ${YELLOW}VirtualBox Adapter:${NC}"
echo -e "    During script  →  NAT        (internet for packages)"
echo -e "    After done     →  Host-Only  (DHCP server for clients)"
echo ""
