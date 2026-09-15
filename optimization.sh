#!/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Arch Linux Optimization + Setup${NC}"
echo -e "${BLUE}========================================${NC}"

# Check root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Run as root: sudo ./setup-optimize.sh${NC}" 
   exit 1
fi

# Get real user
REAL_USER=${SUDO_USER:-$(logname 2>/dev/null)}
if [[ -z "$REAL_USER" ]]; then
    echo -e "${RED}Cannot determine user. Run with sudo.${NC}"
    exit 1
fi
USER_HOME=$(eval echo ~$REAL_USER)

# ============================================
# 1. Locale & Timezone
# ============================================
echo -e "\n${YELLOW}[1/9] Setting locale to UTF-8 & timezone...${NC}"

# Generate en_US.UTF-8 locale
if ! grep -q "en_US.UTF-8" /etc/locale.gen; then
    sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    locale-gen
fi
echo "LANG=en_US.UTF-8" > /etc/locale.conf
export LANG=en_US.UTF-8

# Set timezone
ln -sf /usr/share/zoneinfo/Asia/Kathmandu /etc/localtime
hwclock --systohc --utc

echo -e "${GREEN}✓ Locale: en_US.UTF-8${NC}"
echo -e "${GREEN}✓ Timezone: Asia/Kathmandu${NC}"

# ============================================
# 2. Nano as default editor
# ============================================
echo -e "\n${YELLOW}[2/9] Setting nano as default editor...${NC}"

if ! grep -q "EDITOR=nano" /etc/environment 2>/dev/null; then
    echo "EDITOR=nano" >> /etc/environment
    echo "VISUAL=nano" >> /etc/environment
fi
export EDITOR=nano
export VISUAL=nano

echo -e "${GREEN}✓ Nano configured${NC}"

# ============================================
# 3. Password feedback (****)
# ============================================
echo -e "\n${YELLOW}[3/9] Enabling password feedback...${NC}"

SUDOERS_FILE="/etc/sudoers.d/pwfeedback"
if [[ ! -f "$SUDOERS_FILE" ]]; then
    echo "Defaults pwfeedback" > "$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"
    echo -e "${GREEN}✓ Password feedback enabled${NC}"
else
    echo -e "${GREEN}✓ Already enabled${NC}"
fi

# ============================================
# 4. Install yay AUR helper
# ============================================
echo -e "\n${YELLOW}[4/9] Installing yay AUR helper...${NC}"

if command -v yay &> /dev/null; then
    echo -e "${GREEN}✓ Yay already installed${NC}"
else
    pacman -S --needed --noconfirm git base-devel
    
    rm -rf /tmp/yay-build
    mkdir -p /tmp/yay-build
    cd /tmp/yay-build
    sudo -u $REAL_USER git clone https://aur.archlinux.org/yay-bin.git
    cd yay-bin
    sudo -u $REAL_USER makepkg -si --noconfirm
    cd /tmp
    rm -rf /tmp/yay-build
    
    echo -e "${GREEN}✓ Yay installed${NC}"
fi

# ============================================
# 5. Pacman optimization
# ============================================
echo -e "\n${YELLOW}[5/9] Optimizing pacman...${NC}"

if [[ ! -f /etc/pacman.conf.bak ]]; then
    cp /etc/pacman.conf /etc/pacman.conf.bak
    echo -e "Backup: /etc/pacman.conf.bak"
fi

sed -i 's/#Color/Color/' /etc/pacman.conf
sed -i 's/#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf

if ! grep -q "ILoveCandy" /etc/pacman.conf; then
    sed -i '/^ParallelDownloads/a ILoveCandy' /etc/pacman.conf
fi

if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
fi

pacman -Sy

echo -e "${GREEN}✓ Pacman optimized${NC}"

# ============================================
# 6. Zen kernel installation
# ============================================
echo -e "\n${YELLOW}[6/9] Installing Zen kernel...${NC}"

if pacman -Q linux-zen &> /dev/null; then
    echo -e "${GREEN}✓ Zen kernel already installed${NC}"
else
    pacman -S --noconfirm linux-zen linux-zen-headers
    echo -e "${GREEN}✓ Zen kernel installed${NC}"
fi

# ============================================
# 7. CachyOS Performance Optimizations
# ============================================
echo -e "\n${YELLOW}[7/9] Applying CachyOS optimizations...${NC}"

# Sysctl tuning
mkdir -p /etc/sysctl.d
cat > /etc/sysctl.d/99-cachyos.conf << 'EOF'
# Memory & I/O
vm.swappiness=100
vm.vfs_cache_pressure=50
vm.dirty_bytes=536870912
vm.dirty_background_bytes=268435456
vm.dirty_writeback_centisecs=3000
vm.page-cluster=0

# System stability
kernel.nmi_watchdog=0
kernel.unprivileged_userns_clone=1
kernel.kptr_restrict=1

# Network
net.core.netdev_max_backlog=5000
fs.file-max=2097152

# Logging
kernel.printk=3 3 3 3
EOF
sysctl -p /etc/sysctl.d/99-cachyos.conf 2>/dev/null || true

# Udev rules for I/O scheduler
mkdir -p /etc/udev/rules.d
cat > /etc/udev/rules.d/60-ioschedulers.rules << 'EOF'
# I/O scheduler assignment
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="kyber"
ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF

# Modprobe: blacklist watchdog modules
mkdir -p /etc/modprobe.d
cat > /etc/modprobe.d/blacklist-watchdog.conf << 'EOF'
blacklist iTCO_wdt
blacklist sp5100_tco
EOF

# Systemd journal limit
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/size-limit.conf << 'EOF'
[Journal]
SystemMaxUse=50M
RuntimeMaxUse=50M
Compress=yes
EOF

# Systemd service defaults
mkdir -p /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/timeouts.conf << 'EOF'
[Manager]
DefaultTimeoutStartSec=15s
DefaultTimeoutStopSec=10s
DefaultLimitNOFILE=2048:2097152
EOF

mkdir -p /etc/systemd/user.conf.d
cat > /etc/systemd/user.conf.d/limits.conf << 'EOF'
[Manager]
DefaultLimitNOFILE=1024:1048576
EOF

# Systemd-resolved (DNS)
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/cachyos.conf << 'EOF'
[Resolve]
DNS=1.1.1.1 8.8.8.8
FallbackDNS=1.0.0.1 8.8.4.4
EOF
systemctl restart systemd-resolved 2>/dev/null || true

# THP defragmentation
mkdir -p /etc/tmpfiles.d
cat > /etc/tmpfiles.d/cachyos-thp.conf << 'EOF'
w /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise
EOF

# Coredump cleanup (3 days)
cat >> /etc/tmpfiles.d/cachyos-thp.conf << 'EOF'
e /var/lib/systemd/coredump - - - - 3d
EOF

systemd-tmpfiles --create 2>/dev/null || true

# PCI latency optimization
mkdir -p /etc/sysctl.d
cat > /etc/sysctl.d/99-pci-latency.conf << 'EOF'
# Audio devices PCI latency
dev.i915.perf_sample_rate = 0
EOF

echo -e "${GREEN}✓ CachyOS optimizations applied${NC}"

# ============================================
# 8. ZRAM + Zswap with Zstd compression
# ============================================
echo -e "\n${YELLOW}[8/9] Setting up ZRAM with Zswap & Zstd...${NC}"

# Install zram-generator if not present
if ! pacman -Q zram-generator &> /dev/null; then
    pacman -S --noconfirm zram-generator
fi

mkdir -p /etc/systemd/zram-generator.conf.d
cat > /etc/systemd/zram-generator.conf.d/zram.conf << 'EOF'
[zram0]
compression-algorithm = zstd
zram-size = ram / 2
swap-priority = 100
EOF

systemctl restart systemd-zram-setup@zram0.service 2>/dev/null || true

# Configure Zswap (kernel level compression)
mkdir -p /etc/sysctl.d
cat > /etc/sysctl.d/99-zswap.conf << 'EOF'
vm.zswap.enabled = 1
vm.zswap.compressor = zstd
vm.zswap.max_pool_percent = 25
EOF
sysctl -p /etc/sysctl.d/99-zswap.conf 2>/dev/null || true

echo -e "${GREEN}✓ ZRAM + Zswap (Zstd) configured${NC}"

# ============================================
# 9. TLP Battery Optimization
# ============================================
echo -e "\n${YELLOW}[9/9] Setting up TLP...${NC}"

pacman -R --noconfirm thermald laptop-mode-tools 2>/dev/null || true
pacman -S --needed --noconfirm tlp

mkdir -p /etc/tlp.d
cat > /etc/tlp.d/00-optimization.conf << 'EOF'
# CPU governors
CPU_SCALING_GOVERNOR_ON_AC=schedutil
CPU_SCALING_GOVERNOR_ON_BAT=powersave

# Energy performance
CPU_ENERGY_PERF_POLICY_ON_AC=balance_performance
CPU_ENERGY_PERF_POLICY_ON_BAT=power

# Turbo boost
CPU_BOOST_ON_AC=1
CPU_BOOST_ON_BAT=0

# Platform profile
PLATFORM_PROFILE_ON_AC=balanced
PLATFORM_PROFILE_ON_BAT=low-power

# Disk link power management
SATA_LINKPWR_ON_AC=med_power_with_dipm
SATA_LINKPWR_ON_BAT=min_power

# PCIe power management
PCIE_ASPM_ON_AC=default
PCIE_ASPM_ON_BAT=powersupersave

# Runtime power management
RUNTIME_PM_ON_AC=on
RUNTIME_PM_ON_BAT=auto

# WiFi power saving
WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=on

# Audio power saving
SOUND_POWER_SAVE_ON_AC=0
SOUND_POWER_SAVE_ON_BAT=1

# USB autosuspend
USB_AUTOSUSPEND=1
EOF

systemctl enable tlp.service 2>/dev/null || true
systemctl start tlp.service 2>/dev/null || true
systemctl mask systemd-rfkill.service systemd-rfkill.socket 2>/dev/null || true

# SSD TRIM
systemctl enable fstrim.timer 2>/dev/null || true

echo -e "${GREEN}✓ TLP + TRIM configured${NC}"

# ============================================
# 10. Fish Shell Setup
# ============================================
echo -e "\n${YELLOW}[10/9] Installing Fish shell...${NC}"

if ! command -v fish &> /dev/null; then
    pacman -S --noconfirm fish
fi

# Set Fish as default shell
chsh -s /usr/bin/fish $REAL_USER

# Create Fish config directory
mkdir -p "$USER_HOME/.config/fish"
chown -R $REAL_USER:$REAL_USER "$USER_HOME/.config/fish"

# Fish abbreviations
cat > "$USER_HOME/.config/fish/conf.d/abbr.fish" << 'EOF'
# System abbreviations
abbr -a update 'sudo pacman -Syu && yay -Syu'
abbr -a install 'sudo pacman -S'
abbr -a remove 'sudo pacman -Rns'
abbr -a search 'pacman -Ss'
abbr -a clean 'sudo pacman -Sc && yay -Sc'
abbr -a info 'pacman -Si'
abbr -a owned 'pacman -Qo'

# Navigation
abbr -a .. 'cd ..'
abbr -a ... 'cd ../..'
abbr -a ll 'ls -lah'
abbr -a la 'ls -la'

# System info
abbr -a zram 'cat /proc/swaps && echo "---" && free -h'
abbr -a tlp-check 'sudo tlp-stat -s'
abbr -a disk 'df -h'
abbr -a mem 'free -h'
EOF

chown $REAL_USER:$REAL_USER "$USER_HOME/.config/fish/conf.d/abbr.fish"

echo -e "${GREEN}✓ Fish shell installed & configured${NC}"

# ============================================
# 11. UFW Firewall Setup
# ============================================
echo -e "\n${YELLOW}[11/9] Setting up UFW firewall...${NC}"

if ! command -v ufw &> /dev/null; then
    pacman -S --noconfirm ufw
fi

# Default policies
ufw --force enable
ufw default deny incoming
ufw default allow outgoing

# Allow SSH (optional)
read -p "Allow SSH (port 22)? (y/N): " allow_ssh
if [[ $allow_ssh =~ ^[Yy]$ ]]; then
    ufw allow 22/tcp
    echo -e "${GREEN}✓ SSH allowed${NC}"
fi

systemctl enable ufw.service 2>/dev/null || true

echo -e "${GREEN}✓ UFW firewall configured${NC}"

# ============================================
# 12. Directory Structure
# ============================================
echo -e "\n${YELLOW}[12/9] Creating directory structure...${NC}"

mkdir -p "$USER_HOME"/{.config,Documents,Downloads,Pictures,Videos,Music,Projects}
chown -R $REAL_USER:$REAL_USER "$USER_HOME"/.config
chown -R $REAL_USER:$REAL_USER "$USER_HOME"/{Documents,Downloads,Pictures,Videos,Music,Projects}

echo -e "${GREEN}✓ Directories created${NC}"

# ============================================
# Summary
# ============================================
echo -e "\n${BLUE}========================================${NC}"
echo -e "${GREEN}✓ Setup Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}Configured:${NC}"
echo -e "  ✓ Locale: en_US.UTF-8"
echo -e "  ✓ Timezone: Asia/Kathmandu"
echo -e "  ✓ Nano default editor"
echo -e "  ✓ Password feedback (****)"
echo -e "  ✓ Yay AUR helper"
echo -e "  ✓ Pacman optimized"
echo -e "  ✓ Zen kernel installed"
echo -e "  ✓ CachyOS system tuning"
echo -e "  ✓ ZRAM + Zswap (Zstd compression)"
echo -e "  ✓ TLP battery optimization + TRIM"
echo -e "  ✓ Fish shell (default for $REAL_USER)"
echo -e "  ✓ UFW firewall (deny in, allow out)"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  • Reboot for all changes: ${BLUE}reboot${NC}"
echo -e "  • Check TLP: ${BLUE}sudo tlp-stat -s${NC}"
echo -e "  • Check ZRAM: ${BLUE}cat /proc/swaps && free -h${NC}"
echo -e "  • Check UFW: ${BLUE}sudo ufw status${NC}"
echo -e "  • Fish abbr: type in Fish shell for auto-complete hints"
echo ""
