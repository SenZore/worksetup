#!/bin/bash
# ============================================================
#  AUTHOR    : ADAM SANJAYA XI TJKT 2
#  PROJECT   : OpenSSH + ISC-DHCP Server — FULL FRESH SETUP
#  TARGET    : Debian 13 (Trixie) — VirtualBox
#  ADAPTER 1 : enp0s3  → Host-Only  → DHCP Server
#  ADAPTER 2 : enp0s8  → NAT        → Internet
#  SERVER IP : 192.168.56.1
#  DHCP RANGE: 192.168.56.50 – 192.168.56.100
# ============================================================

[[ $EUID -ne 0 ]] && { echo "[ERROR] Run as root: sudo bash setup_adam.sh"; exit 1; }

G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; R='\033[0;31m'; N='\033[0m'
info()    { echo -e "\n${C}[INFO]${N}  $1"; }
success() { echo -e "${G}[OK]${N}    $1"; }
warn()    { echo -e "${Y}[WARN]${N}  $1"; }
error()   { echo -e "${R}[ERR]${N}   $1"; exit 1; }
banner()  { echo -e "\n${Y}══════════════════════════════════════════${N}\n  $1\n${Y}══════════════════════════════════════════${N}"; }

# ── Fixed interface + network config ─────────────────────────
HOSTONLY="enp0s3"         # Adapter 1 — Host-Only — DHCP server
NAT="enp0s8"              # Adapter 2 — NAT       — internet

SERVER_IP="192.168.56.1"
SUBNET="192.168.56.0"
NETMASK="255.255.255.0"
PREFIX="24"
BROADCAST="192.168.56.255"
RANGE_START="192.168.56.50"
RANGE_END="192.168.56.100"
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
echo "  ╠══════════════════════════════════════════════════════╣"
echo "  ║  Adapter 1 : enp0s3  →  Host-Only  (DHCP Server)    ║"
echo "  ║  Adapter 2 : enp0s8  →  NAT        (Internet)       ║"
echo "  ║  Server IP : 192.168.56.1                            ║"
echo "  ║  DHCP Range: 192.168.56.50 – 192.168.56.100         ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo ""

# ════════════════════════════════════════════════════════════
#  PHASE 1 — WIPE EVERYTHING
# ════════════════════════════════════════════════════════════
banner "PHASE 1 — WIPING PREVIOUS INSTALLS"

info "Stopping any running services..."
systemctl stop isc-dhcp-server 2>/dev/null || true
systemctl stop ssh             2>/dev/null || true
systemctl disable isc-dhcp-server 2>/dev/null || true
systemctl disable ssh             2>/dev/null || true

info "Purging packages..."
apt-get purge -y openssh-server openssh-client isc-dhcp-server isc-dhcp-common ifupdown 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
success "Packages purged."

info "Deleting all old config files..."
rm -f  /etc/ssh/sshd_config*
rm -f  /etc/motd
rm -f  /etc/dhcp/dhcpd.conf*
rm -f  /etc/default/isc-dhcp-server*
rm -rf /var/lib/dhcp/
mkdir -p /var/lib/dhcp
touch /var/lib/dhcp/dhcpd.leases
success "Old configs deleted."

info "Resetting /etc/network/interfaces to loopback only..."
cat > /etc/network/interfaces <<'EOF'
# /etc/network/interfaces
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback
EOF
success "interfaces file reset."

info "Flushing IPs on both interfaces..."
ip addr flush dev "$HOSTONLY" 2>/dev/null || true
ip addr flush dev "$NAT"      2>/dev/null || true
ip link set "$HOSTONLY" down  2>/dev/null || true
ip link set "$NAT"      down  2>/dev/null || true
success "Interfaces flushed."

# ════════════════════════════════════════════════════════════
#  PHASE 2 — FIX APT SOURCES
# ════════════════════════════════════════════════════════════
banner "PHASE 2 — FIXING APT SOURCES"

SOURCES="/etc/apt/sources.list"

info "Nuking all cdrom lines..."
grep -vi "cdrom" "$SOURCES" > /tmp/sources.clean 2>/dev/null || true
mv /tmp/sources.clean "$SOURCES"
success "cdrom entries removed."

info "Disabling all sources.list.d entries..."
for f in /etc/apt/sources.list.d/*.list; do
  [[ -f "$f" ]] && mv "$f" "${f}.disabled" && warn "Disabled: $f"
done
success "sources.list.d cleaned."

info "Writing clean Debian 13 Trixie mirrors..."
cat > "$SOURCES" <<'EOF'
# /etc/apt/sources.list — ADAM SANJAYA XI TJKT 2 — Debian 13 Trixie
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
EOF
success "Clean sources.list written."

# ════════════════════════════════════════════════════════════
#  PHASE 3 — BRING UP NAT FOR INTERNET
# ════════════════════════════════════════════════════════════
banner "PHASE 3 — INTERNET VIA $NAT (NAT)"

info "Bringing up $NAT via DHCP..."
ip link set "$NAT" up
dhclient "$NAT" 2>/dev/null || true
sleep 3

NAT_IP=$(ip -4 addr show "$NAT" 2>/dev/null | awk '/inet / {print $2}' | head -1)
if [[ -n "$NAT_IP" ]]; then
  success "$NAT got IP: $NAT_IP"
else
  warn "Could not get IP on $NAT. Make sure Adapter 2 = NAT in VirtualBox."
fi

if ping -c 2 -W 3 8.8.8.8 &>/dev/null; then
  success "Internet reachable."
else
  warn "No internet ping. apt-get update may fail."
fi

# ════════════════════════════════════════════════════════════
#  PHASE 4 — UPDATE AND INSTALL
# ════════════════════════════════════════════════════════════
banner "PHASE 4 — INSTALLING PACKAGES"

info "Running apt-get update..."
apt-get update -y || error "apt-get update failed. Check Adapter 2 is NAT in VirtualBox."
success "Package list updated."

info "Installing packages..."
apt-get install -y openssh-server isc-dhcp-server net-tools ifupdown || \
  error "Package install failed."
success "All packages installed."

# ════════════════════════════════════════════════════════════
#  PHASE 5 — STATIC IP ON HOST-ONLY (enp0s3)
# ════════════════════════════════════════════════════════════
banner "PHASE 5 — STATIC IP ON $HOSTONLY (Host-Only)"

info "Assigning $SERVER_IP to $HOSTONLY..."
ip link set "$HOSTONLY" up
sleep 1
ip addr flush dev "$HOSTONLY" 2>/dev/null || true
ip addr add "$SERVER_IP/$PREFIX" broadcast "$BROADCAST" dev "$HOSTONLY"
sleep 1

if ip addr show "$HOSTONLY" | grep -q "inet $SERVER_IP"; then
  success "Static IP $SERVER_IP confirmed on $HOSTONLY."
else
  error "Failed to assign $SERVER_IP to $HOSTONLY. Run: ip a"
fi

info "Persisting static IP to /etc/network/interfaces..."
cat >> /etc/network/interfaces <<EOF

# enp0s3 — ADAM SANJAYA XI TJKT 2 — Host-Only Static IP
auto $HOSTONLY
iface $HOSTONLY inet static
    address   $SERVER_IP
    netmask   $NETMASK
    broadcast $BROADCAST

# enp0s8 — ADAM SANJAYA XI TJKT 2 — NAT (DHCP)
auto $NAT
iface $NAT inet dhcp
EOF
success "interfaces file updated."

# ════════════════════════════════════════════════════════════
#  PHASE 6 — DHCP SERVER CONFIG
# ════════════════════════════════════════════════════════════
banner "PHASE 6 — DHCP SERVER CONFIG"

info "Writing /etc/dhcp/dhcpd.conf..."
cat > /etc/dhcp/dhcpd.conf <<EOF
# ============================================================
#  dhcpd.conf — ADAM SANJAYA XI TJKT 2
#  Server IP : $SERVER_IP
#  Interface : $HOSTONLY (Host-Only)
#  Range     : $RANGE_START – $RANGE_END (51 hosts)
# ============================================================

authoritative;
log-facility local7;

default-lease-time  $DEFAULT_LEASE;   # 1 hour
min-lease-time      $MIN_LEASE;       # 10 minutes
max-lease-time      $MAX_LEASE;       # 2 hours

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

info "Binding DHCP to $HOSTONLY..."
cat > /etc/default/isc-dhcp-server <<EOF
# ADAM SANJAYA XI TJKT 2
INTERFACESv4="$HOSTONLY"
INTERFACESv6=""
EOF
success "DHCP bound to $HOSTONLY."

# ════════════════════════════════════════════════════════════
#  PHASE 7 — SSH CONFIG
# ════════════════════════════════════════════════════════════
banner "PHASE 7 — SSH CONFIG"

info "Writing /etc/ssh/sshd_config..."
cat > /etc/ssh/sshd_config <<'EOF'
# sshd_config — ADAM SANJAYA XI TJKT 2
Port 22
ListenAddress 0.0.0.0
AddressFamily inet
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
PermitEmptyPasswords no
AuthorizedKeysFile .ssh/authorized_keys
LoginGraceTime 60
MaxAuthTries 4
MaxSessions 20
StrictModes yes
X11Forwarding yes
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
UseDNS no
Subsystem sftp /usr/lib/openssh/sftp-server
EOF
success "sshd_config written."

cat > /etc/motd <<'EOF'

  ╔══════════════════════════════════════════════════════╗
  ║         ADAM SANJAYA — XI TJKT 2                     ║
  ║         Debian 13 Server | VirtualBox                ║
  ║         OpenSSH + ISC-DHCP Server                    ║
  ║   Unauthorized access is strictly prohibited.       ║
  ╚══════════════════════════════════════════════════════╝

EOF
success "MOTD written."

# ════════════════════════════════════════════════════════════
#  PHASE 8 — START SERVICES
# ════════════════════════════════════════════════════════════
banner "PHASE 8 — STARTING SERVICES"

systemctl daemon-reexec

# SSH
info "Starting SSH..."
systemctl enable ssh
systemctl restart ssh
sleep 1
systemctl is-active --quiet ssh \
  && success "ssh             → RUNNING ✓" \
  || warn    "ssh → FAILED  (systemctl status ssh)"

# Verify IP still on interface before DHCP starts
if ! ip addr show "$HOSTONLY" | grep -q "inet $SERVER_IP"; then
  warn "IP gone — re-applying..."
  ip addr add "$SERVER_IP/$PREFIX" broadcast "$BROADCAST" dev "$HOSTONLY"
  ip link set "$HOSTONLY" up
  sleep 1
fi

# DHCP
info "Starting isc-dhcp-server..."
systemctl enable isc-dhcp-server
systemctl restart isc-dhcp-server
sleep 2
systemctl is-active --quiet isc-dhcp-server \
  && success "isc-dhcp-server → RUNNING ✓" \
  || {
    warn "isc-dhcp-server → FAILED. Logs:"
    journalctl -u isc-dhcp-server --no-pager -n 15
  }

# UFW
if command -v ufw &>/dev/null; then
  banner "PHASE 9 — FIREWALL"
  ufw allow 22/tcp  comment "SSH  - ADAM SANJAYA"
  ufw allow 67/udp  comment "DHCP - ADAM SANJAYA"
  ufw allow 68/udp  comment "DHCP - ADAM SANJAYA"
  ufw --force enable && success "UFW rules applied."
fi

# ════════════════════════════════════════════════════════════
#  DONE
# ════════════════════════════════════════════════════════════
echo ""
echo "  ╔══════════════════════════════════════════════════════╗"
echo -e "  ║  ${G}SETUP COMPLETE — ADAM SANJAYA XI TJKT 2${N}             ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo ""
echo -e "  ${C}Host-Only (DHCP) :${N} $HOSTONLY → $SERVER_IP"
echo -e "  ${C}NAT (Internet)   :${N} $NAT → $NAT_IP"
echo -e "  ${C}DHCP Range       :${N} $RANGE_START – $RANGE_END  (51 hosts)"
echo -e "  ${C}Lease Times      :${N} Default 1h | Min 10m | Max 2h"
echo -e "  ${C}SSH Port         :${N} 22"
echo -e "  ${C}Domain           :${N} adamsanjaya.local"
echo ""
echo -e "  ${Y}PuTTY / CMD:${N}"
echo -e "    Host : $SERVER_IP   Port : 22"
echo -e "    CMD  : ssh root@$SERVER_IP"
echo ""
