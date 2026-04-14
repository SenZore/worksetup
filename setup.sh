#!/bin/bash
# ============================================================
#  PROJECT   : OpenSSH + ISC-DHCP Server Setup
#  AUTHOR    : ADAM SANJAYA XI TJKT 2
#  TARGET    : Debian 13 (Trixie) — VirtualBox
#  INTERFACE : enp0s3 (VirtualBox Ethernet)
#  DHCP RANGE: 192.168.1.50 – 192.168.1.100
#  DATE      : $(date +%Y-%m-%d)
# ============================================================

# ── Safety: must run as root ────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Please run this script as root: sudo bash setup_adam.sh"
  exit 1
fi

# ── Color helpers ───────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERR]${NC}  $1"; exit 1; }

IFACE="enp0s3"
SERVER_IP="192.168.1.1"
SUBNET="192.168.1.0"
NETMASK="255.255.255.0"
RANGE_START="192.168.1.50"
RANGE_END="192.168.1.100"
BROADCAST="192.168.1.255"
DNS1="8.8.8.8"
DNS2="8.8.4.4"
MIN_LEASE="600"
MAX_LEASE="7200"
DEFAULT_LEASE="3600"

echo ""
echo "============================================================"
echo "  ADAM SANJAYA XI TJKT 2 — Server Setup Script"
echo "  OpenSSH + ISC-DHCP | Debian 13 | VirtualBox"
echo "============================================================"
echo ""

# ── STEP 1: Update package list ─────────────────────────────
info "Updating package list..."
apt-get update -y || error "apt-get update failed. Check your internet connection."
success "Package list updated."

# ── STEP 2: Install packages ────────────────────────────────
info "Installing openssh-server and isc-dhcp-server..."
apt-get install -y openssh-server isc-dhcp-server net-tools || \
  error "Package installation failed."
success "Packages installed."

# ── STEP 3: Set static IP on enp0s3 via /etc/network/interfaces
info "Configuring static IP ($SERVER_IP) on $IFACE..."

INTERFACES_FILE="/etc/network/interfaces"

# Backup original
cp "$INTERFACES_FILE" "${INTERFACES_FILE}.bak.$(date +%s)"

# Remove any existing enp0s3 block
sed -i '/^# enp0s3/,/^$/d' "$INTERFACES_FILE" 2>/dev/null
sed -i "/iface $IFACE/d" "$INTERFACES_FILE" 2>/dev/null
sed -i "/allow-hotplug $IFACE/d" "$INTERFACES_FILE" 2>/dev/null
sed -i "/auto $IFACE/d" "$INTERFACES_FILE" 2>/dev/null

cat >> "$INTERFACES_FILE" <<EOF

# enp0s3 — ADAM SANJAYA XI TJKT 2 — Static for DHCP Server
auto $IFACE
iface $IFACE inet static
    address $SERVER_IP
    netmask $NETMASK
    broadcast $BROADCAST
EOF

success "Static IP configured in $INTERFACES_FILE."

# Bring interface up
ifdown "$IFACE" 2>/dev/null; ifup "$IFACE" 2>/dev/null
success "$IFACE brought up with IP $SERVER_IP."

# ── STEP 4: Configure ISC-DHCP Server ───────────────────────
info "Writing DHCP configuration..."

cat > /etc/dhcp/dhcpd.conf <<EOF
# ============================================================
#  dhcpd.conf
#  Author  : ADAM SANJAYA XI TJKT 2
#  Server  : $SERVER_IP  |  Interface: $IFACE
#  Range   : $RANGE_START – $RANGE_END  (51 hosts)
# ============================================================

# --- Global Timing ---
default-lease-time $DEFAULT_LEASE;   # 1 hour
min-lease-time     $MIN_LEASE;       # 10 minutes
max-lease-time     $MAX_LEASE;       # 2 hours

# --- Authoritative DHCP server for this subnet ---
authoritative;

# --- Logging ---
log-facility local7;

# ---- Subnet Declaration --------------------------------
subnet $SUBNET netmask $NETMASK {

    # Dynamic pool: 50 hosts (192.168.1.50 – 192.168.1.100)
    range $RANGE_START $RANGE_END;

    # Default gateway (this server)
    option routers $SERVER_IP;

    # Subnet mask
    option subnet-mask $NETMASK;

    # Broadcast address
    option broadcast-address $BROADCAST;

    # DNS servers
    option domain-name-servers $DNS1, $DNS2;

    # Domain name
    option domain-name "adamsanjaya.local";

    # Lease times (inherit global values)
    default-lease-time $DEFAULT_LEASE;
    min-lease-time     $MIN_LEASE;
    max-lease-time     $MAX_LEASE;
}
EOF

success "DHCP config written to /etc/dhcp/dhcpd.conf."

# ── STEP 5: Set DHCP interface ───────────────────────────────
info "Setting DHCP server to listen on $IFACE..."

# Debian 13 uses /etc/default/isc-dhcp-server
DHCP_DEFAULT="/etc/default/isc-dhcp-server"
cp "$DHCP_DEFAULT" "${DHCP_DEFAULT}.bak.$(date +%s)" 2>/dev/null

sed -i "s/^INTERFACESv4=.*/INTERFACESv4=\"$IFACE\"/" "$DHCP_DEFAULT"
sed -i "s/^INTERFACESv6=.*/INTERFACESv6=\"\"/" "$DHCP_DEFAULT"

# If line doesn't exist yet, add it
grep -q "^INTERFACESv4" "$DHCP_DEFAULT" || echo "INTERFACESv4=\"$IFACE\"" >> "$DHCP_DEFAULT"
grep -q "^INTERFACESv6" "$DHCP_DEFAULT" || echo "INTERFACESv6=\"\""      >> "$DHCP_DEFAULT"

success "DHCP interface set to $IFACE."

# ── STEP 6: Configure OpenSSH ────────────────────────────────
info "Configuring OpenSSH server..."

SSHD_CONF="/etc/ssh/sshd_config"
cp "$SSHD_CONF" "${SSHD_CONF}.bak.$(date +%s)"

# Apply settings (uncomment or set)
declare -A SSH_SETTINGS=(
  ["Port"]="22"
  ["ListenAddress"]="0.0.0.0"
  ["PermitRootLogin"]="yes"
  ["PasswordAuthentication"]="yes"
  ["PubkeyAuthentication"]="yes"
  ["PermitEmptyPasswords"]="no"
  ["X11Forwarding"]="yes"
  ["PrintMotd"]="no"
  ["UseDNS"]="no"
  ["LoginGraceTime"]="60"
  ["MaxAuthTries"]="4"
  ["MaxSessions"]="20"
)

for KEY in "${!SSH_SETTINGS[@]}"; do
  VAL="${SSH_SETTINGS[$KEY]}"
  # Remove any existing line (commented or not) and add clean one
  sed -i "s/^#\?${KEY}.*/${KEY} ${VAL}/" "$SSHD_CONF"
  grep -q "^${KEY}" "$SSHD_CONF" || echo "${KEY} ${VAL}" >> "$SSHD_CONF"
done

# ── Custom MOTD banner (shown on SSH login) ──────────────────
cat > /etc/motd <<'MOTD'

  ╔══════════════════════════════════════════════════════╗
  ║         ADAM SANJAYA — XI TJKT 2                     ║
  ║         Debian 13 Server | VirtualBox                ║
  ║         OpenSSH + ISC-DHCP Server                    ║
  ║                                                      ║
  ║   Unauthorized access is strictly prohibited.       ║
  ╚══════════════════════════════════════════════════════╝

MOTD

success "SSH configured (Port 22, PasswordAuth ON, PermitRootLogin ON)."

# ── STEP 7: Enable & restart services ───────────────────────
info "Enabling and starting services..."

systemctl enable ssh
systemctl restart ssh
success "SSH service started."

systemctl enable isc-dhcp-server
systemctl restart isc-dhcp-server
DHCP_STATUS=$(systemctl is-active isc-dhcp-server)
if [[ "$DHCP_STATUS" == "active" ]]; then
  success "ISC-DHCP service started."
else
  warn "DHCP service may have failed. Run: systemctl status isc-dhcp-server"
fi

# ── STEP 8: Firewall (if ufw is present) ─────────────────────
if command -v ufw &>/dev/null; then
  info "Configuring UFW firewall rules..."
  ufw allow 22/tcp    comment "SSH - ADAM SANJAYA"
  ufw allow 67/udp    comment "DHCP - ADAM SANJAYA"
  ufw allow 68/udp    comment "DHCP Client - ADAM SANJAYA"
  ufw --force enable
  success "UFW rules applied."
else
  warn "UFW not found — skipping firewall config (optional)."
fi

# ── STEP 9: Verify services ──────────────────────────────────
echo ""
info "Service status check:"
systemctl is-active --quiet ssh           && success "ssh          → RUNNING" || warn "ssh          → NOT RUNNING"
systemctl is-active --quiet isc-dhcp-server && success "isc-dhcp-server → RUNNING" || warn "isc-dhcp-server → NOT RUNNING"

# ── STEP 10: Print connection summary ────────────────────────
echo ""
echo "============================================================"
echo -e "${GREEN}  ✅  SETUP COMPLETE — ADAM SANJAYA XI TJKT 2${NC}"
echo "============================================================"
echo ""
echo -e "  ${CYAN}Server IP   :${NC} $SERVER_IP"
echo -e "  ${CYAN}SSH Port    :${NC} 22"
echo -e "  ${CYAN}DHCP Range  :${NC} $RANGE_START – $RANGE_END"
echo -e "  ${CYAN}Lease Time  :${NC} Default=${DEFAULT_LEASE}s  Min=${MIN_LEASE}s  Max=${MAX_LEASE}s"
echo -e "  ${CYAN}Interface   :${NC} $IFACE"
echo -e "  ${CYAN}Domain      :${NC} adamsanjaya.local"
echo ""
echo -e "  ${YELLOW}PuTTY / CMD Connection:${NC}"
echo -e "    Host    : $SERVER_IP"
echo -e "    Port    : 22"
echo -e "    User    : root  (or your Debian username)"
echo -e "    CMD     : ssh root@$SERVER_IP"
echo ""
echo -e "  ${YELLOW}VirtualBox Reminder:${NC}"
echo -e "    • Set VM Adapter to: Host-Only  OR  Bridged"
echo -e "    • After install, you may disable the adapter"
echo -e "    • Clients on 192.168.1.x will auto-get IPs"
echo ""
echo "============================================================"
