#!/bin/bash

# Personal Arch Linux Setup Script
# Run as root on a fresh Arch install

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Arch Linux Personal Setup Script${NC}"
echo -e "${BLUE}========================================${NC}"

# Check root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Run as root: sudo ./setup.sh${NC}" 
   exit 1
fi

# Get the real user (not root)
REAL_USER=${SUDO_USER:-$(logname 2>/dev/null)}
if [[ -z "$REAL_USER" ]]; then
    echo -e "${RED}Cannot determine user. Run with sudo.${NC}"
    exit 1
fi
USER_HOME=$(eval echo ~$REAL_USER)

# ============================================
# 1. Set nano as default editor
# ============================================
echo -e "\n${YELLOW}[1/6] Setting nano as default editor...${NC}"
if ! grep -q "EDITOR=nano" /etc/environment 2>/dev/null; then
    echo "EDITOR=nano" >> /etc/environment
    echo "VISUAL=nano" >> /etc/environment
fi
export EDITOR=nano
export VISUAL=nano
echo -e "${GREEN}✓ Nano configured${NC}"

# ============================================
# 2. Enable password feedback (****)
# ============================================
echo -e "\n${YELLOW}[2/6] Enabling password feedback...${NC}"
SUDOERS_FILE="/etc/sudoers.d/pwfeedback"
if [[ ! -f "$SUDOERS_FILE" ]]; then
    echo "Defaults pwfeedback" > "$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"
    echo -e "${GREEN}✓ Password feedback enabled${NC}"
else
    echo -e "${GREEN}✓ Already enabled${NC}"
fi

# ============================================
# 3. Install yay
# ============================================
echo -e "\n${YELLOW}[3/6] Installing yay AUR helper...${NC}"
if command -v yay &> /dev/null; then
    echo -e "${GREEN}✓ Yay already installed${NC}"
else
    pacman -S --needed --noconfirm git base-devel
    cd /tmp
    sudo -u $REAL_USER git clone https://aur.archlinux.org/yay-bin.git
    cd yay-bin
    sudo -u $REAL_USER makepkg -si --noconfirm
    cd /tmp
    rm -rf yay-bin
    echo -e "${GREEN}✓ Yay installed${NC}"
fi

# ============================================
# 4. Install and configure TLP
# ============================================
echo -e "\n${YELLOW}[4/6] Setting up TLP for battery optimization...${NC}"
pacman -S --needed --noconfirm tlp

# Create TLP config focused on battery saving
mkdir -p /etc/tlp.d
cat > /etc/tlp.d/00-battery-optimization.conf << 'EOF'
# Battery-focused TLP configuration

# CPU - Power saving on battery, balanced on AC
CPU_SCALING_GOVERNOR_ON_AC=schedutil
CPU_SCALING_GOVERNOR_ON_BAT=powersave

CPU_ENERGY_PERF_POLICY_ON_AC=balance_performance
CPU_ENERGY_PERF_POLICY_ON_BAT=power

# Disable turbo boost on battery to save power
CPU_BOOST_ON_AC=1
CPU_BOOST_ON_BAT=0

# Platform profiles (if supported by hardware)
PLATFORM_PROFILE_ON_AC=balanced
PLATFORM_PROFILE_ON_BAT=low-power

# Aggressive power saving for disks on battery
SATA_LINKPWR_ON_AC=med_power_with_dipm
SATA_LINKPWR_ON_BAT=min_power

# PCIe power management
PCIE_ASPM_ON_AC=default
PCIE_ASPM_ON_BAT=powersupersave

# Enable runtime PM for all devices on battery
RUNTIME_PM_ON_AC=on
RUNTIME_PM_ON_BAT=auto

# WiFi power saving on battery
WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=on

# Enable audio power saving on battery
SOUND_POWER_SAVE_ON_AC=0
SOUND_POWER_SAVE_ON_BAT=1

# USB autosuspend
USB_AUTOSUSPEND=1
EOF

# Enable TLP
systemctl enable tlp.service
systemctl start tlp.service
systemctl mask systemd-rfkill.service systemd-rfkill.socket 2>/dev/null || true

echo -e "${GREEN}✓ TLP configured for battery optimization${NC}"

# ============================================
# 5. Optimize pacman
# ============================================
echo -e "\n${YELLOW}[5/6] Optimizing pacman...${NC}"

# Backup if not already done
[[ ! -f /etc/pacman.conf.bak ]] && cp /etc/pacman.conf /etc/pacman.conf.bak

# Enable color and parallel downloads
sed -i 's/#Color/Color/' /etc/pacman.conf
sed -i 's/#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf

# Add eye candy (pacman eating dots)
if ! grep -q "ILoveCandy" /etc/pacman.conf; then
    sed -i '/^ParallelDownloads/a ILoveCandy' /etc/pacman.conf
fi

# Enable multilib (for 32-bit support)
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
fi

pacman -Sy

echo -e "${GREEN}✓ Pacman optimized${NC}"

# ============================================
# 6. Performance optimizations
# ============================================
echo -e "\n${YELLOW}[6/6] Applying performance optimizations...${NC}"

# Enable TRIM for SSDs
systemctl enable fstrim.timer

# Reduce swappiness (less swapping = better performance)
echo "vm.swappiness=10" > /etc/sysctl.d/99-swappiness.conf
sysctl -p /etc/sysctl.d/99-swappiness.conf

# System responsiveness improvements
cat > /etc/sysctl.d/99-performance.conf << 'EOF'
# Increase file watchers (for IDEs, file managers)
fs.inotify.max_user_watches=524288

# Better cache management
vm.vfs_cache_pressure=50

# Increase max map count (helps with games, browsers)
vm.max_map_count=2147483642
EOF
sysctl -p /etc/sysctl.d/99-performance.conf

# Optimize I/O schedulers
cat > /etc/udev/rules.d/60-ioschedulers.rules << 'EOF'
# Optimal schedulers for different drive types
ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
EOF

# Optimize makepkg for faster AUR builds
if [[ ! -f /etc/makepkg.conf.bak ]]; then
    cp /etc/makepkg.conf /etc/makepkg.conf.bak
fi
CORES=$(nproc)
sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$CORES\"/" /etc/makepkg.conf
sed -i "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -z - --threads=0)/" /etc/makepkg.conf

# Enable systemd-oomd (prevents system freeze on low memory)
systemctl enable --now systemd-oomd

# Optimize systemd journal size
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/size-limit.conf << 'EOF'
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=50M
Compress=yes
EOF
systemctl restart systemd-journald

# Add useful aliases
if ! grep -q "# Personal Aliases" "$USER_HOME/.bashrc" 2>/dev/null; then
    cat >> "$USER_HOME/.bashrc" << 'EOF'

# Personal Aliases
alias update='sudo pacman -Syu && yay -Syu'
alias install='sudo pacman -S'
alias remove='sudo pacman -Rns'
alias search='pacman -Ss'
alias clean='sudo pacman -Sc && yay -Sc'
alias ll='ls -lah'
alias ..='cd ..'
alias ...='cd ../..'
EOF
    chown $REAL_USER:$REAL_USER "$USER_HOME/.bashrc"
    echo -e "${GREEN}✓ Useful aliases added to .bashrc${NC}"
fi

echo -e "${GREEN}✓ Performance optimizations applied${NC}"

# ============================================
# Summary
# ============================================
echo -e "\n${BLUE}========================================${NC}"
echo -e "${GREEN}✓ Setup Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}✓${NC} Nano is default editor"
echo -e "${GREEN}✓${NC} Password feedback enabled (****)"
echo -e "${GREEN}✓${NC} Yay AUR helper installed"
echo -e "${GREEN}✓${NC} TLP optimized for battery life"
echo -e "${GREEN}✓${NC} Pacman optimized (parallel downloads)"
echo -e "${GREEN}✓${NC} Performance improvements applied"
echo ""
echo -e "${YELLOW}→ Reboot recommended for all changes to take effect${NC}"
echo -e "${YELLOW}→ Check TLP status: tlp-stat -s${NC}"
echo ""
