#!/bin/bash
# ============================================================
#  AUTHOR    : ADAM SANJAYA XI TJKT 2
#  PROJECT   : OpenSSH + ISC-DHCP Server — FULL FRESH SETUP
#  TARGET    : Debian 13 (Trixie) — VirtualBox
#  ADAPTERS  : Adapter 1 (enp0s3) = Host-Only → DHCP Server
#              Adapter 2 (enp0s8) = NAT       → Internet
#  DHCP RANGE: 192.168.1.50 – 192.168.1.100
#  NOTE      : Wipes everything first, then builds from zero
# ============================================================
set -euo pipefail
# ── Must run as root ─────────────────────────────────────────
[[ $EUID -ne 0 ]] && { echo "[ERROR] Run as root: sudo bash $0"; exit 1; }
# ── Colors & helpers ─────────────────────────────────────────
G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m' R='\033[0;31m' N='\033[0m'
info()    { echo -e "\n${C}[INFO]${N}  $1"; }
ok()      { echo -e "${G}[OK]${N}    $1"; }
warn()    { echo -e "${Y}[WARN]${N}  $1"; }
die()     { echo -e "${R}[ERR]${N}   $1"; exit 1; }
banner()  { echo -e "\n${Y}════════════════════════════════════════${N}\n  $1\n${Y}════════════════════════════════════════${N}"; }
# ── Config ───────────────────────────────────────────────────
IF_HOSTONLY="enp0s3"        # Adapter 1 — Host-Only (DHCP server)
IF_NAT="enp0s8"             # Adapter 2 — NAT (internet)
SERVER_IP="192.168.1.1"
SUBNET="192.168.1.0"
NETMASK="255.255.255.0"
PREFIX="24"
BROADCAST="192.168.1.255"
RANGE_START="192.168.1.50"
RANGE_END="192.168.1.100"
DNS1="8.8.8.8"
DNS2="8.8.4.4"
DOMAIN="adamsanjaya.local"
clear
cat <<'HEADER'
  ╔══════════════════════════════════════════════════════╗
  ║       ADAM SANJAYA XI TJKT 2 — FRESH SETUP          ║
  ║       OpenSSH + ISC-DHCP | Debian 13 | VirtualBox   ║
  ╚══════════════════════════════════════════════════════╝
  Dual Adapter Layout:
    Adapter 1 (enp0s3) → Host-Only  → DHCP Server
    Adapter 2 (enp0s8) → NAT        → Internet Access
  This script will:
  1. Wipe ALL previous SSH & DHCP configs
  2. Fix apt sources (remove cdrom, add online mirrors)
  3. Install everything fresh
  4. Configure static IP on enp0s3, DHCP client on enp0s8
  5. Configure & start DHCP + SSH (auto-start on boot)
HEADER
read -rp "  Press ENTER to begin or Ctrl+C to cancel..." _
# ════════════════════════════════════════════════════════════
#  PHASE 1 — WIPE EVERYTHING
# ════════════════════════════════════════════════════════════
banner "PHASE 1 — WIPING PREVIOUS INSTALLS"
info "Stopping existing services..."
systemctl stop isc-dhcp-server ssh sshd 2>/dev/null || true
info "Purging old packages..."
apt-get purge -y openssh-server isc-dhcp-server isc-dhcp-common 2>/dev/null || true
apt-get autoremove --purge -y 2>/dev/null || true
ok "Packages purged."
info "Removing leftover config files..."
rm -rf /etc/ssh/sshd_config{,.bak*,.original*} /etc/motd
rm -rf /etc/dhcp/dhcpd.conf{,.bak*} /etc/default/isc-dhcp-server
rm -rf /var/lib/dhcp/dhcpd.leases{,~}
mkdir -p /var/lib/dhcp && touch /var/lib/dhcp/dhcpd.leases
rm -f /etc/apt/sources.list.{original.bak*,bak*}
ok "Old configs cleaned."
info "Resetting /etc/network/interfaces (loopback only)..."
cat > /etc/network/interfaces <<'EOF'
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).
source /etc/network/interfaces.d/*
# The loopback network interface
auto lo
iface lo inet loopback
EOF
ok "interfaces reset."
info "Flushing IPs on $IF_HOSTONLY..."
ip addr flush dev "$IF_HOSTONLY" 2>/dev/null || true
ok "Flush done."
# ════════════════════════════════════════════════════════════
#  PHASE 2 — FIX APT SOURCES
# ════════════════════════════════════════════════════════════
banner "PHASE 2 — FIXING APT SOURCES"
SOURCES="/etc/apt/sources.list"
info "Removing cdrom entries & writing clean mirrors..."
cat > "$SOURCES" <<'EOF'
# /etc/apt/sources.list — ADAM SANJAYA XI TJKT 2
# Debian 13 (Trixie) — Clean online mirrors
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
EOF
# Disable any extras in sources.list.d
for f in /etc/apt/sources.list.d/*.list 2>/dev/null; do
  [[ -f "$f" ]] && mv "$f" "${f}.disabled" && warn "Disabled: $(basename "$f")"
done
ok "APT sources fixed."
# ════════════════════════════════════════════════════════════
#  PHASE 3 — GET INTERNET VIA NAT ADAPTER (enp0s8)
# ════════════════════════════════════════════════════════════
banner "PHASE 3 — CONNECTING TO INTERNET VIA $IF_NAT"
info "Bringing up $IF_NAT (NAT) via DHCP..."
ip link set "$IF_NAT" up
dhclient "$IF_NAT" 2>/dev/null || true
sleep 2
if ping -c2 -W3 8.8.8.8 &>/dev/null; then
  ok "Internet reachable via $IF_NAT (NAT)."
else
  warn "Cannot ping 8.8.8.8 — make sure Adapter 2 is NAT."
  warn "Continuing anyway..."
fi
# ════════════════════════════════════════════════════════════
#  PHASE 4 — INSTALL PACKAGES
# ════════════════════════════════════════════════════════════
banner "PHASE 4 — INSTALLING PACKAGES"
info "Updating package list..."
apt-get update -y || die "apt-get update failed. Check Adapter 2 (NAT)."
ok "Package list updated."
info "Installing openssh-server, isc-dhcp-server, net-tools, ifupdown..."
apt-get install -y openssh-server isc-dhcp-server net-tools ifupdown || \
  die "Package install failed."
ok "All packages installed."
# ════════════════════════════════════════════════════════════
#  PHASE 5 — CONFIGURE NETWORK INTERFACES (persistent)
# ════════════════════════════════════════════════════════════
banner "PHASE 5 — CONFIGURING NETWORK INTERFACES"
info "Writing persistent network config..."
cat > /etc/network/interfaces <<EOF
# /etc/network/interfaces — ADAM SANJAYA XI TJKT 2
# ─────────────────────────────────────────────────
source /etc/network/interfaces.d/*
# Loopback
auto lo
iface lo inet loopback
# ── Adapter 1: Host-Only — DHCP Server ──────────────────────
auto $IF_HOSTONLY
iface $IF_HOSTONLY inet static
    address   $SERVER_IP
    netmask   $NETMASK
    broadcast $BROADCAST
# ── Adapter 2: NAT — Internet Access ────────────────────────
auto $IF_NAT
iface $IF_NAT inet dhcp
EOF
ok "Network interfaces written (both adapters)."
info "Applying static IP $SERVER_IP on $IF_HOSTONLY now..."
ip addr flush dev "$IF_HOSTONLY" 2>/dev/null || true
ip addr add "$SERVER_IP/$PREFIX" broadcast "$BROADCAST" dev "$IF_HOSTONLY"
ip link set "$IF_HOSTONLY" up
sleep 1
ip addr show "$IF_HOSTONLY" | grep -q "inet $SERVER_IP" \
  && ok "Static IP $SERVER_IP/$PREFIX live on $IF_HOSTONLY." \
  || die "Failed to assign $SERVER_IP. Check interface name with 'ip a'."
# ════════════════════════════════════════════════════════════
#  PHASE 6 — CONFIGURE ISC-DHCP-SERVER (keep defaults, add range)
# ════════════════════════════════════════════════════════════
banner "PHASE 6 — CONFIGURING DHCP SERVER"
DHCPD_CONF="/etc/dhcp/dhcpd.conf"
info "Writing $DHCPD_CONF (default config + active subnet range)..."
cat > "$DHCPD_CONF" <<EOF
# dhcpd.conf
#
# Sample configuration file for ISC dhcpd
#
# Attention: If /etc/ltsp/dhcpd.conf exists, that will be used as
# configuration file instead of this file.
#
# option definitions common to all supported networks...
option domain-name "$DOMAIN";
option domain-name-servers $DNS1, $DNS2;
default-lease-time 600;
max-lease-time 7200;
# The ddns-update-style parameter controls whether or not the server will
# attempt to do a DNS update when a lease is confirmed. We default to the
# behavior of the version 2 packages ('none', since DHCP v2 didn't
# have support for DDNS.)
ddns-update-style none;
# If this DHCP server is the official DHCP server for the local
# network, the authoritative directive should be uncommented.
authoritative;
# Use this to send dhcp log messages to a different log file (you also
# have to hack syslog.conf to complete the redirection).
#log-facility local7;
# No service will be given on this subnet, but declaring it helps the
# DHCP server to understand the network topology.
#subnet 10.152.187.0 netmask 255.255.255.0 {
#}
# This is a very basic subnet declaration.
subnet $SUBNET netmask $NETMASK {
  range $RANGE_START $RANGE_END;
  option routers $SERVER_IP;
  option broadcast-address $BROADCAST;
}
# This is an example for a fixed-address host
# (a host which receives a static IP from DHCP)
#host fantasia {
#  hardware ethernet 08:00:07:26:c0:a5;
#  fixed-address fantasia.example.com;
#}
# You can declare a class of clients and then do address allocation
# based on that.  The example below shows a case where all clients
# in a certain class get addresses on the 10.17.224/24 subnet, and all
# other clients get addresses on the 10.0.29/24 subnet.
#class "foo" {
#  match if substring (option vendor-class-identifier, 0, 4) = "SUNW";
#}
#shared-network 224-29 {
#  subnet 10.17.224.0 netmask 255.255.255.0 {
#    option routers rtr-224.example.org;
#  }
#  subnet 10.0.29.0 netmask 255.255.255.0 {
#    option routers rtr-29.example.org;
#  }
#  pool {
#    allow members of "foo";
#    range 10.17.224.10 10.17.224.250;
#  }
#  pool {
#    deny members of "foo";
#    range 10.0.29.10 10.0.29.230;
#  }
#}
EOF
ok "dhcpd.conf written (default style, range active)."
info "Binding isc-dhcp-server to $IF_HOSTONLY..."
cat > /etc/default/isc-dhcp-server <<EOF
# Defaults for isc-dhcp-server (sourced by /etc/init.d/isc-dhcp-server)
# ADAM SANJAYA XI TJKT 2
# On what interfaces should the DHCP server (dhcpd) serve DHCP requests?
INTERFACESv4="$IF_HOSTONLY"
INTERFACESv6=""
EOF
ok "DHCP bound to $IF_HOSTONLY."
# ════════════════════════════════════════════════════════════
#  PHASE 7 — CONFIGURE OPENSSH
# ════════════════════════════════════════════════════════════
banner "PHASE 7 — CONFIGURING OPENSSH"
info "Writing /etc/ssh/sshd_config..."
cat > /etc/ssh/sshd_config <<'EOF'
# ============================================================
#  sshd_config — ADAM SANJAYA XI TJKT 2
#  Debian 13 (Trixie) | VirtualBox
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
ok "sshd_config written."
info "Writing MOTD banner..."
cat > /etc/motd <<'EOF'
  ╔══════════════════════════════════════════════════════╗
  ║         ADAM SANJAYA — XI TJKT 2                     ║
  ║         Debian 13 Server | VirtualBox                ║
  ║         OpenSSH + ISC-DHCP Server                    ║
  ║                                                      ║
  ║   Unauthorized access is strictly prohibited.       ║
  ╚══════════════════════════════════════════════════════╝
EOF
ok "MOTD written."
# ════════════════════════════════════════════════════════════
#  PHASE 8 — ENABLE & START SERVICES (auto-start on boot)
# ════════════════════════════════════════════════════════════
banner "PHASE 8 — ENABLING & STARTING SERVICES"
systemctl daemon-reexec
# ── SSH ──────────────────────────────────────────────────────
info "Enabling SSH (auto-start on boot)..."
systemctl enable ssh
systemctl restart ssh
sleep 1
systemctl is-active --quiet ssh \
  && ok "ssh             → RUNNING ✓  (auto-start: enabled)" \
  || warn "ssh             → FAILED  (run: systemctl status ssh)"
# ── Verify static IP before DHCP start ───────────────────────
if ! ip addr show "$IF_HOSTONLY" | grep -q "inet $SERVER_IP"; then
  warn "IP lost — re-applying $SERVER_IP..."
  ip addr add "$SERVER_IP/$PREFIX" broadcast "$BROADCAST" dev "$IF_HOSTONLY"
  ip link set "$IF_HOSTONLY" up
  sleep 1
fi
# ── DHCP ─────────────────────────────────────────────────────
info "Enabling isc-dhcp-server (auto-start on boot)..."
systemctl enable isc-dhcp-server
systemctl restart isc-dhcp-server
sleep 2
systemctl is-active --quiet isc-dhcp-server \
  && ok "isc-dhcp-server → RUNNING ✓  (auto-start: enabled)" \
  || { warn "isc-dhcp-server → FAILED"; journalctl -u isc-dhcp-server --no-pager -n 10; }
# ── Networking service (ifupdown) ────────────────────────────
info "Enabling networking service (auto-start on boot)..."
systemctl enable networking
ok "networking      → ENABLED ✓  (auto-start: enabled)"
# ════════════════════════════════════════════════════════════
#  PHASE 9 — UFW FIREWALL (if present)
# ════════════════════════════════════════════════════════════
if command -v ufw &>/dev/null; then
  banner "PHASE 9 — FIREWALL RULES"
  ufw allow 22/tcp  comment "SSH  - ADAM SANJAYA"
  ufw allow 67/udp  comment "DHCP - ADAM SANJAYA"
  ufw allow 68/udp  comment "DHCP - ADAM SANJAYA"
  ufw --force enable
  ok "UFW rules applied."
fi
# ════════════════════════════════════════════════════════════
#  DONE — SUMMARY
# ════════════════════════════════════════════════════════════
echo ""
echo "  ╔══════════════════════════════════════════════════════╗"
echo -e "  ║  ${G}SETUP COMPLETE — ADAM SANJAYA XI TJKT 2${N}             ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo ""
echo -e "  ${Y}═══ NETWORK LAYOUT ════════════════════════════════${N}"
echo -e "  ${C}Adapter 1 (${IF_HOSTONLY})${N} → Host-Only → Static $SERVER_IP/$PREFIX"
echo -e "  ${C}Adapter 2 (${IF_NAT})${N} → NAT       → DHCP (internet)"
echo ""
echo -e "  ${Y}═══ DHCP SERVER ═══════════════════════════════════${N}"
echo -e "  ${C}DHCP Range     :${N} $RANGE_START – $RANGE_END  (51 hosts)"
echo -e "  ${C}Lease Default  :${N} 600s   (10 min)"
echo -e "  ${C}Lease Max      :${N} 7200s  (2 hours)"
echo -e "  ${C}Domain         :${N} $DOMAIN"
echo ""
echo -e "  ${Y}═══ SSH SERVER ════════════════════════════════════${N}"
echo -e "  ${C}SSH Port       :${N} 22"
echo -e "  ${C}Connect        :${N} ssh root@$SERVER_IP"
echo ""
echo -e "  ${Y}═══ AUTO-START ON BOOT ════════════════════════════${N}"
echo -e "  ${G}✓${N} networking       (ifupdown — applies static IP)"
echo -e "  ${G}✓${N} ssh              (OpenSSH server)"
echo -e "  ${G}✓${N} isc-dhcp-server  (DHCP server on $IF_HOSTONLY)"
echo ""
echo -e "  ${Y}═══ CONFIG FILE LOCATIONS ═════════════════════════${N}"
echo -e "  ${C}Network        :${N} /etc/network/interfaces"
echo -e "  ${C}DHCP Config    :${N} /etc/dhcp/dhcpd.conf"
echo -e "  ${C}DHCP Interface :${N} /etc/default/isc-dhcp-server"
echo -e "  ${C}DHCP Leases    :${N} /var/lib/dhcp/dhcpd.leases"
echo -e "  ${C}SSH Config     :${N} /etc/ssh/sshd_config"
echo -e "  ${C}Login Banner   :${N} /etc/motd"
echo -e "  ${C}APT Sources    :${N} /etc/apt/sources.list"
echo ""
echo -e "  ${Y}═══ USEFUL COMMANDS ═══════════════════════════════${N}"
echo -e "  ${C}Check DHCP status  :${N} systemctl status isc-dhcp-server"
echo -e "  ${C}Check SSH status   :${N} systemctl status ssh"
echo -e "  ${C}View DHCP leases   :${N} cat /var/lib/dhcp/dhcpd.leases"
echo -e "  ${C}View active IPs    :${N} ip a"
echo -e "  ${C}Restart DHCP       :${N} systemctl restart isc-dhcp-server"
echo -e "  ${C}Restart SSH        :${N} systemctl restart ssh"
echo -e "  ${C}View DHCP logs     :${N} journalctl -u isc-dhcp-server -f"
echo ""
