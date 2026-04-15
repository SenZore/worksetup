#!/bin/bash
# ============================================================
#  AUTHOR    : ADAM SANJAYA XI TJKT 2
#  PROJECT   : OpenSSH + ISC-DHCP Server — FULL FRESH SETUP
#  TARGET    : Debian 13 (Trixie) — VirtualBox
#  ADAPTER 1 : Host-Only  → DHCP Server (auto-detected)
#  ADAPTER 2 : NAT        → Internet/packages (auto-detected)
#  DHCP RANGE: auto-detected subnet, .50–.100 (51 hosts)
# ============================================================

[[ $EUID -ne 0 ]] && { echo "[ERROR] Run as root: sudo bash setup_adam.sh"; exit 1; }

# ── Colors ───────────────────────────────────────────────────
G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; R='\033[0;31m'; N='\033[0m'
info()    { echo -e "\n${C}[INFO]${N}  $1"; }
success() { echo -e "${G}[OK]${N}    $1"; }
warn()    { echo -e "${Y}[WARN]${N}  $1"; }
error()   { echo -e "${R}[ERR]${N}   $1"; exit 1; }
banner()  { echo -e "\n${Y}══════════════════════════════════════════${N}\n  $1\n${Y}══════════════════════════════════════════${N}"; }

clear
echo ""
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║       ADAM SANJAYA XI TJKT 2 — FRESH SETUP          ║"
echo "  ║       OpenSSH + ISC-DHCP | Debian 13 | VirtualBox   ║"
echo "  ║       Adapter 1: Host-Only | Adapter 2: NAT         ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo ""

# ════════════════════════════════════════════════════════════
#  PHASE 1 — AUTO-DETECT INTERFACES
# ════════════════════════════════════════════════════════════
banner "PHASE 1 — DETECTING INTERFACES"

info "Bringing up all interfaces to scan..."
for iface in $(ls /sys/class/net | grep -v lo); do
  ip link set "$iface" up 2>/dev/null
done
sleep 1

# Try to get IPs via DHCP on all non-loopback interfaces
info "Requesting DHCP leases on all interfaces..."
for iface in $(ls /sys/class/net | grep -v lo); do
  dhclient "$iface" 2>/dev/null &
done
sleep 4
kill %% 2>/dev/null; wait 2>/dev/null

info "Scanning interfaces..."

NAT_IFACE=""
HOSTONLY_IFACE=""

# The NAT interface will have a default route / gateway assigned
# The Host-Only interface will have an IP but no gateway

for iface in $(ls /sys/class/net | grep -v lo); do
  IP=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
  GW=$(ip route show dev "$iface" 2>/dev/null | awk '/default/ {print $3}' | head -1)

  [[ -z "$IP" ]] && continue

  echo "    Found: $iface → IP=$IP  GW=${GW:-none}"

  if [[ -n "$GW" ]]; then
    NAT_IFACE="$iface"
    NAT_IP="$IP"
  else
    HOSTONLY_IFACE="$iface"
    HOSTONLY_CURRENT_IP="$IP"
  fi
done

# Fallback: if only one interface found, ask
[[ -z "$NAT_IFACE" ]]     && error "Could not detect NAT interface (Adapter 2). Make sure Adapter 2 is set to NAT in VirtualBox."
[[ -z "$HOSTONLY_IFACE" ]] && error "Could not detect Host-Only interface (Adapter 1). Make sure Adapter 1 is set to Host-Only in VirtualBox."

success "NAT interface      : $NAT_IFACE  (IP: $NAT_IP)"
success "Host-Only interface: $HOSTONLY_IFACE  (current IP: $HOSTONLY_CURRENT_IP)"

# ── Derive subnet from Host-Only interface's current IP ──────
# e.g. 192.168.56.101 → base = 192.168.56, server = 192.168.56.1
IFACE="$HOSTONLY_IFACE"
BASE_SUBNET=$(echo "$HOSTONLY_CURRENT_IP" | cut -d. -f1-3)   # e.g. 192.168.56

SERVER_IP="${BASE_SUBNET}.1"
SUBNET="${BASE_SUBNET}.0"
NETMASK="255.255.255.0"
PREFIX="24"
BROADCAST="${BASE_SUBNET}.255"
RANGE_START="${BASE_SUBNET}.50"
RANGE_END="${BASE_SUBNET}.100"
DNS1="8.8.8.8"
DNS2="8.8.4.4"
DEFAULT_LEASE="3600"
MIN_LEASE="600"
MAX_LEASE="7200"

echo ""
echo -e "  ${C}Subnet detected  :${N} $SUBNET/24"
echo -e "  ${C}Server IP will be:${N} $SERVER_IP"
echo -e "  ${C}DHCP range       :${N} $RANGE_START – $RANGE_END  (51 hosts)"
echo ""

# ════════════════════════════════════════════════════════════
#  PHASE 2 — WIPE EVERYTHING
# ════════════════════════════════════════════════════════════
banner "PHASE 2 — WIPING PREVIOUS INSTALLS"

info "Stopping services..."
systemctl stop isc-dhcp-server 2>/dev/null || true
systemctl stop ssh             2>/dev/null || true

info "Purging packages..."
apt-get purge -y openssh-server isc-dhcp-server isc-dhcp-common ifupdown 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
success "Packages purged."

info "Removing old config files..."
rm -f /etc/ssh/sshd_config* /etc/motd
rm -f /etc/dhcp/dhcpd.conf* /etc/default/isc-dhcp-server*
rm -f /var/lib/dhcp/dhcpd.leases 2>/dev/null || true
mkdir -p /var/lib/dhcp && touch /var/lib/dhcp/dhcpd.leases

# Reset interfaces file to loopback only
cat > /etc/network/interfaces <<'EOF'
# /etc/network/interfaces
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback
EOF
success "All old configs deleted."

# ════════════════════════════════════════════════════════════
#  PHASE 3 — FIX APT SOURCES
# ════════════════════════════════════════════════════════════
banner "PHASE 3 — FIXING APT SOURCES"

SOURCES="/etc/apt/sources.list"

info "Removing all cdrom entries..."
grep -vi "cdrom" "$SOURCES" > /tmp/sources.clean 2>/dev/null || true
mv /tmp/sources.clean "$SOURCES"

info "Disabling all sources.list.d files..."
for f in /etc/apt/sources.list.d/*.list; do
  [[ -f "$f" ]] && mv "$f" "${f}.disabled" && warn "Disabled: $f"
done

info "Writing clean Debian 13 Trixie mirrors..."
cat > "$SOURCES" <<'EOF'
# /etc/apt/sources.list — ADAM SANJAYA XI TJKT 2 — Debian 13 Trixie
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
EOF
success "Clean sources.list written."

# ════════════════════════════════════════════════════════════
#  PHASE 4 — UPDATE AND INSTALL (using NAT interface)
# ════════════════════════════════════════════════════════════
banner "PHASE 4 — INSTALLING PACKAGES (via $NAT_IFACE NAT)"

if ping -c 2 -W 3 8.8.8.8 &>/dev/null; then
  success "Internet reachable via $NAT_IFACE."
else
  warn "No internet detected. Trying apt-get update anyway..."
fi

info "Running apt-get update..."
apt-get update -y || error "apt-get update failed. Check Adapter 2 is set to NAT in VirtualBox."
success "Package list updated."

info "Installing packages..."
apt-get install -y openssh-server isc-dhcp-server net-tools ifupdown || \
  error "Install failed."
success "openssh-server, isc-dhcp-server, net-tools, ifupdown installed."

# ════════════════════════════════════════════════════════════
#  PHASE 5 — SET STATIC IP ON HOST-ONLY INTERFACE
# ════════════════════════════════════════════════════════════
banner "PHASE 5 — STATIC IP ON $IFACE (Host-Only)"

info "Flushing $IFACE and assigning $SERVER_IP..."
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$SERVER_IP/$PREFIX" broadcast "$BROADCAST" dev "$IFACE"
ip link set "$IFACE" up
sleep 1

ip addr show "$IFACE" | grep -q "inet $SERVER_IP" \
  && success "Static IP $SERVER_IP/$PREFIX confirmed on $IFACE." \
  || error "Failed to assign $SERVER_IP to $IFACE."

# Persist to /etc/network/interfaces
cat >> /etc/network/interfaces <<EOF

# $IFACE — ADAM SANJAYA XI TJKT 2 — Host-Only Static IP
auto $IFACE
iface $IFACE inet static
    address   $SERVER_IP
    netmask   $NETMASK
    broadcast $BROADCAST
EOF
success "Static IP persisted to /etc/network/interfaces."

# ════════════════════════════════════════════════════════════
#  PHASE 6 — CONFIGURE DHCP SERVER
# ════════════════════════════════════════════════════════════
banner "PHASE 6 — DHCP CONFIG"

info "Writing /etc/dhcp/dhcpd.conf..."
cat > /etc/dhcp/dhcpd.conf <<EOF
# ============================================================
#  dhcpd.conf — ADAM SANJAYA XI TJKT 2
#  Server    : $SERVER_IP
#  Interface : $IFACE (Host-Only)
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

info "Binding DHCP server to $IFACE..."
cat > /etc/default/isc-dhcp-server <<EOF
# ADAM SANJAYA XI TJKT 2
INTERFACESv4="$IFACE"
INTERFACESv6=""
EOF
success "DHCP bound to $IFACE."

# ════════════════════════════════════════════════════════════
#  PHASE 7 — CONFIGURE OPENSSH
# ════════════════════════════════════════════════════════════
banner "PHASE 7 — SSH CONFIG"

info "Writing fresh /etc/ssh/sshd_config..."
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
  || warn    "ssh             → FAILED  (systemctl status ssh)"

# Re-verify IP before DHCP start
if ! ip addr show "$IFACE" | grep -q "inet $SERVER_IP"; then
  warn "IP lost — re-applying $SERVER_IP..."
  ip addr add "$SERVER_IP/$PREFIX" broadcast "$BROADCAST" dev "$IFACE"
  ip link set "$IFACE" up
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
    warn "isc-dhcp-server → FAILED"
    echo ""
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
echo -e "  ${C}Host-Only Interface :${N} $IFACE"
echo -e "  ${C}NAT Interface       :${N} $NAT_IFACE"
echo -e "  ${C}Server IP           :${N} $SERVER_IP"
echo -e "  ${C}SSH Port            :${N} 22"
echo -e "  ${C}DHCP Range          :${N} $RANGE_START – $RANGE_END (51 hosts)"
echo -e "  ${C}Lease Default/Min/Max:${N} ${DEFAULT_LEASE}s / ${MIN_LEASE}s / ${MAX_LEASE}s"
echo -e "  ${C}Domain              :${N} adamsanjaya.local"
echo ""
echo -e "  ${Y}PuTTY / CMD:${N}"
echo -e "    Host : $SERVER_IP   Port : 22"
echo -e "    CMD  : ssh root@$SERVER_IP"
echo ""
