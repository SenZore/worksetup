#!/bin/bash
# ============================================================
#  PROJECT   : OpenSSH + ISC-DHCP Server Setup
#  AUTHOR    : ADAM SANJAYA XI TJKT 2
#  TARGET    : Debian 13 (Trixie) — VirtualBox
#  INTERFACE : enp0s3 (VirtualBox Ethernet)
#  DHCP RANGE: 192.168.1.50 – 192.168.1.100
#  FIX       : Auto-repairs cdrom apt sources → online mirrors
# ============================================================

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Please run this script as root: sudo bash setup_adam.sh"
  exit 1
fi

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

# ════════════════════════════════════════════════════════════
# STEP 0: FIX APT SOURCES — remove cdrom, add online mirrors
# ════════════════════════════════════════════════════════════
info "Fixing /etc/apt/sources.list (removing cdrom entries)..."

SOURCES="/etc/apt/sources.list"
cp "$SOURCES" "${SOURCES}.bak.$(date +%s)"

# Comment out ALL cdrom lines
sed -i 's|^deb cdrom:|#deb cdrom:|g'         "$SOURCES"
sed -i 's|^deb-src cdrom:|#deb-src cdrom:|g' "$SOURCES"

# Add online Debian 13 Trixie mirrors if not already present
if ! grep -qE "deb.debian.org/debian[[:space:]]+trixie" "$SOURCES" 2>/dev/null; then
  info "Adding Debian 13 (Trixie) online mirrors..."
  cat >> "$SOURCES" <<'REPO'

# ── Added by ADAM SANJAYA XI TJKT 2 setup script ──────────
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
REPO
  success "Online Debian 13 mirrors added."
else
  success "Online mirror already present — skipping."
fi

# Disable any broken VBoxAdditions cdrom sources in sources.list.d
for f in /etc/apt/sources.list.d/*.list; do
  if grep -q "cdrom:" "$f" 2>/dev/null; then
    warn "Disabling broken source: $f"
    mv "$f" "${f}.disabled"
  fi
done

# ── STEP 1: Update package list ─────────────────────────────
info "Running apt-get update..."
apt-get update -y
if [[ $? -ne 0 ]]; then
  error "apt-get update failed.\n  Make sure your VirtualBox network adapter is set to NAT\n  (needs internet to download packages). Switch to Host-Only after."
fi
success "Package list updated."

# ── STEP 2: Install packages ────────────────────────────────
info "Installing openssh-server, isc-dhcp-server, net-tools..."
apt-get install -y openssh-server isc-dhcp-server net-tools || \
  error "Package installation failed."
success "Packages installed."

# ── STEP 3: Set static IP on enp0s3 ─────────────────────────
info "Configuring static IP ($SERVER_IP) on $IFACE..."

INTERFACES_FILE="/etc/network/interfaces"
cp "$INTERFACES_FILE" "${INTERFACES_FILE}.bak.$(date +%s)"

# Remove existing enp0s3 entries cleanly
sed -i "/auto $IFACE/d"          "$INTERFACES_FILE"
sed -i "/allow-hotplug $IFACE/d" "$INTERFACES_FILE"
sed -i "/iface $IFACE/d"         "$INTERFACES_FILE"
sed -i "/address $SERVER_IP/d"   "$INTERFACES_FILE"

cat >> "$INTERFACES_FILE" <<EOF

# enp0s3 — ADAM SANJAYA XI TJKT 2 — Static IP for DHCP Server
auto $IFACE
iface $IFACE inet static
    address   $SERVER_IP
    netmask   $NETMASK
    broadcast $BROADCAST
EOF

success "Static IP written."
ifdown "$IFACE" 2>/dev/null; ifup "$IFACE" 2>/dev/null
success "$IFACE is up with $SERVER_IP."

# ── STEP 4: Configure ISC-DHCP Server ───────────────────────
info "Writing /etc/dhcp/dhcpd.conf..."

cat > /etc/dhcp/dhcpd.conf <<EOF
# ============================================================
#  dhcpd.conf — ADAM SANJAYA XI TJKT 2
#  Server  : $SERVER_IP  |  Interface: $IFACE
#  Range   : $RANGE_START - $RANGE_END  (51 hosts)
# ============================================================

default-lease-time $DEFAULT_LEASE;   # 1 hour
min-lease-time     $MIN_LEASE;       # 10 minutes
max-lease-time     $MAX_LEASE;       # 2 hours

authoritative;
log-facility local7;

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

success "DHCP config written."

# ── STEP 5: Bind DHCP to enp0s3 ─────────────────────────────
info "Setting DHCP server interface..."
DHCP_DEFAULT="/etc/default/isc-dhcp-server"
cp "$DHCP_DEFAULT" "${DHCP_DEFAULT}.bak.$(date +%s)" 2>/dev/null
sed -i "s/^INTERFACESv4=.*/INTERFACESv4=\"$IFACE\"/" "$DHCP_DEFAULT"
sed -i "s/^INTERFACESv6=.*/INTERFACESv6=\"\"/"       "$DHCP_DEFAULT"
grep -q "^INTERFACESv4" "$DHCP_DEFAULT" || echo "INTERFACESv4=\"$IFACE\"" >> "$DHCP_DEFAULT"
grep -q "^INTERFACESv6" "$DHCP_DEFAULT" || echo "INTERFACESv6=\"\""       >> "$DHCP_DEFAULT"
success "DHCP bound to $IFACE."

# ── STEP 6: Configure OpenSSH ────────────────────────────────
info "Configuring /etc/ssh/sshd_config..."
SSHD_CONF="/etc/ssh/sshd_config"
cp "$SSHD_CONF" "${SSHD_CONF}.bak.$(date +%s)"

apply_ssh() {
  local KEY="$1" VAL="$2"
  if grep -qE "^#?${KEY}" "$SSHD_CONF"; then
    sed -i "s|^#\?${KEY}.*|${KEY} ${VAL}|" "$SSHD_CONF"
  else
    echo "${KEY} ${VAL}" >> "$SSHD_CONF"
  fi
}

apply_ssh Port                 22
apply_ssh ListenAddress        0.0.0.0
apply_ssh PermitRootLogin      yes
apply_ssh PasswordAuthentication yes
apply_ssh PubkeyAuthentication yes
apply_ssh PermitEmptyPasswords no
apply_ssh X11Forwarding        yes
apply_ssh PrintMotd            no
apply_ssh UseDNS               no
apply_ssh LoginGraceTime       60
apply_ssh MaxAuthTries         4
apply_ssh MaxSessions          20

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

systemctl enable isc-dhcp-server
systemctl restart isc-dhcp-server

sleep 1

systemctl is-active --quiet ssh             && success "ssh             → RUNNING" \
                                            || warn    "ssh             → FAILED"
systemctl is-active --quiet isc-dhcp-server && success "isc-dhcp-server → RUNNING" \
                                            || warn    "isc-dhcp-server → FAILED  (run: systemctl status isc-dhcp-server)"

# ── STEP 8: UFW firewall (if present) ───────────────────────
if command -v ufw &>/dev/null; then
  info "Applying UFW rules..."
  ufw allow 22/tcp  comment "SSH  - ADAM SANJAYA"
  ufw allow 67/udp  comment "DHCP - ADAM SANJAYA"
  ufw allow 68/udp  comment "DHCP - ADAM SANJAYA"
  ufw --force enable
  success "UFW rules applied."
fi

# ── SUMMARY ──────────────────────────────────────────────────
echo ""
echo "============================================================"
echo -e "${GREEN}  SETUP COMPLETE — ADAM SANJAYA XI TJKT 2${NC}"
echo "============================================================"
echo ""
echo -e "  ${CYAN}Server IP      :${NC} $SERVER_IP"
echo -e "  ${CYAN}SSH Port       :${NC} 22"
echo -e "  ${CYAN}DHCP Range     :${NC} $RANGE_START – $RANGE_END (51 hosts)"
echo -e "  ${CYAN}Lease Default  :${NC} 3600s (1 hour)"
echo -e "  ${CYAN}Lease Min/Max  :${NC} 600s / 7200s"
echo -e "  ${CYAN}Interface      :${NC} $IFACE"
echo -e "  ${CYAN}Domain         :${NC} adamsanjaya.local"
echo ""
echo -e "  ${YELLOW}Connect via PuTTY or CMD:${NC}"
echo -e "    Host : $SERVER_IP"
echo -e "    Port : 22"
echo -e "    CMD  : ssh root@$SERVER_IP"
echo ""
echo -e "  ${YELLOW}VirtualBox Adapter Tip:${NC}"
echo -e "    During install  → set adapter to NAT  (needs internet)"
echo -e "    After install   → switch to Host-Only (DHCP server mode)"
echo ""
echo "============================================================"
