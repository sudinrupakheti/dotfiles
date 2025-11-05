#!/bin/bash

# Arch Linux System Setup Script
# This script requires root privileges

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Arch Linux System Setup Script${NC}"
echo -e "${GREEN}======================================${NC}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}" 
   exit 1
fi

# 1. Set nano as default editor
echo -e "\n${YELLOW}[1/5] Setting nano as default editor...${NC}"
if ! grep -q "EDITOR=nano" /etc/environment; then
    echo "EDITOR=nano" >> /etc/environment
    echo "VISUAL=nano" >> /etc/environment
fi
export EDITOR=nano
export VISUAL=nano
echo -e "${GREEN}✓ Nano set as default editor${NC}"

# 2. Add pwfeedback to sudoers
echo -e "\n${YELLOW}[2/5] Enabling password feedback in sudo...${NC}"
if ! grep -q "Defaults pwfeedback" /etc/sudoers; then
    sed -i '/^Defaults/a Defaults pwfeedback' /etc/sudoers
    echo -e "${GREEN}✓ Password feedback enabled${NC}"
else
    echo -e "${GREEN}✓ Password feedback already enabled${NC}"
fi

# 3. Install yay
echo -e "\n${YELLOW}[3/5] Installing yay AUR helper...${NC}"
if command -v yay &> /dev/null; then
    echo -e "${GREEN}✓ Yay is already installed${NC}"
else
    # Install dependencies
    pacman -S --needed --noconfirm git base-devel
    
    # Get the sudo user (not root)
    SUDO_USER_HOME=$(eval echo ~${SUDO_USER})
    
    # Clone and install yay as the sudo user
    cd /tmp
    sudo -u $SUDO_USER git clone https://aur.archlinux.org/yay.git
    cd yay
    sudo -u $SUDO_USER makepkg -si --noconfirm
    cd ..
    rm -rf yay
    echo -e "${GREEN}✓ Yay installed successfully${NC}"
fi

# 4. Install and configure TLP
echo -e "\n${YELLOW}[4/5] Installing and configuring TLP...${NC}"
pacman -S --needed --noconfirm tlp tlp-rdw

# Backup original config
if [[ ! -f /etc/tlp.conf.bak ]]; then
    cp /etc/tlp.conf /etc/tlp.conf.bak
fi

# Configure TLP for power saving on battery and balanced when plugged in
cat > /etc/tlp.conf << 'EOF'
# TLP Configuration - Power Saving on Battery, Balanced on AC

# CPU Scaling Governor
CPU_SCALING_GOVERNOR_ON_AC=schedutil
CPU_SCALING_GOVERNOR_ON_BAT=powersave

# CPU Energy/Performance Policy
CPU_ENERGY_PERF_POLICY_ON_AC=balance_performance
CPU_ENERGY_PERF_POLICY_ON_BAT=power

# CPU Boost
CPU_BOOST_ON_AC=1
CPU_BOOST_ON_BAT=0

# CPU Min/Max Frequency
CPU_SCALING_MIN_FREQ_ON_AC=800000
CPU_SCALING_MAX_FREQ_ON_AC=9999999
CPU_SCALING_MIN_FREQ_ON_BAT=800000
CPU_SCALING_MAX_FREQ_ON_BAT=2000000

# Platform Profile (if supported)
PLATFORM_PROFILE_ON_AC=balanced
PLATFORM_PROFILE_ON_BAT=low-power

# Disk devices
DISK_DEVICES="nvme0n1 sda"
DISK_APM_LEVEL_ON_AC="254 254"
DISK_APM_LEVEL_ON_BAT="128 128"

# SATA Link Power Management
SATA_LINKPWR_ON_AC=med_power_with_dipm
SATA_LINKPWR_ON_BAT=min_power

# PCI Express Active State Power Management
PCIE_ASPM_ON_AC=default
PCIE_ASPM_ON_BAT=powersupersave

# Runtime Power Management
RUNTIME_PM_ON_AC=on
RUNTIME_PM_ON_BAT=auto

# WiFi Power Saving
WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=on

# Sound Power Saving
SOUND_POWER_SAVE_ON_AC=0
SOUND_POWER_SAVE_ON_BAT=1

# USB Autosuspend
USB_AUTOSUSPEND=1
USB_EXCLUDE_BTUSB=0
USB_EXCLUDE_PHONE=0
USB_EXCLUDE_PRINTER=1
USB_EXCLUDE_WWAN=0

# Battery thresholds (for ThinkPads - adjust if needed)
START_CHARGE_THRESH_BAT0=75
STOP_CHARGE_THRESH_BAT0=80
START_CHARGE_THRESH_BAT1=75
STOP_CHARGE_THRESH_BAT1=80
EOF

# Enable and start TLP
systemctl enable tlp.service
systemctl start tlp.service
systemctl mask systemd-rfkill.service systemd-rfkill.socket 2>/dev/null || true

echo -e "${GREEN}✓ TLP installed and configured${NC}"

# 5. Optimize pacman
echo -e "\n${YELLOW}[5/5] Optimizing pacman...${NC}"

# Backup original pacman.conf
if [[ ! -f /etc/pacman.conf.bak ]]; then
    cp /etc/pacman.conf /etc/pacman.conf.bak
fi

# Enable parallel downloads and color
sed -i 's/#Color/Color/' /etc/pacman.conf
sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
sed -i '/^ParallelDownloads/a ILoveCandy' /etc/pacman.conf

# Enable multilib if not enabled (for 64-bit systems)
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
fi

# Update pacman database
pacman -Sy

echo -e "${GREEN}✓ Pacman optimized${NC}"

# Summary
echo -e "\n${GREEN}======================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo -e "✓ Nano set as default editor"
echo -e "✓ Password feedback enabled in sudo"
echo -e "✓ Yay AUR helper installed"
echo -e "✓ TLP installed and configured"
echo -e "✓ Pacman optimized"
echo -e "\n${YELLOW}Note: You may need to logout and login again for all changes to take effect.${NC}"
echo -e "${YELLOW}TLP status can be checked with: tlp-stat -s${NC}"

# Additional QoL improvements
echo -e "\n${YELLOW}[BONUS] Applying additional QoL improvements...${NC}"

# 6. Enable TRIM for SSDs
echo -e "\n${YELLOW}Enabling weekly TRIM for SSDs...${NC}"
systemctl enable fstrim.timer
echo -e "${GREEN}✓ TRIM timer enabled${NC}"

# 7. Reduce swappiness for better performance
echo -e "\n${YELLOW}Optimizing swappiness...${NC}"
if ! grep -q "vm.swappiness" /etc/sysctl.d/99-swappiness.conf 2>/dev/null; then
    echo "vm.swappiness=10" > /etc/sysctl.d/99-swappiness.conf
    sysctl -p /etc/sysctl.d/99-swappiness.conf
    echo -e "${GREEN}✓ Swappiness set to 10${NC}"
else
    echo -e "${GREEN}✓ Swappiness already configured${NC}"
fi

# 8. Improve I/O scheduler
echo -e "\n${YELLOW}Setting optimal I/O schedulers...${NC}"
cat > /etc/udev/rules.d/60-ioschedulers.rules << 'EOFRULES'
# Set deadline scheduler for non-rotating disks (SSDs, NVMe)
ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
# Set BFQ scheduler for rotating disks (HDDs)
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
# Set none scheduler for NVMe (already optimal)
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
EOFRULES
echo -e "${GREEN}✓ I/O schedulers configured${NC}"

# 9. Improve system responsiveness
echo -e "\n${YELLOW}Improving system responsiveness...${NC}"
cat > /etc/sysctl.d/99-performance.conf << 'EOFPERF'
# Increase file watchers
fs.inotify.max_user_watches=524288
# Improve cache pressure
vm.vfs_cache_pressure=50
# Increase max map count (helps with games and some apps)
vm.max_map_count=2147483642
EOFPERF
sysctl -p /etc/sysctl.d/99-performance.conf
echo -e "${GREEN}✓ System responsiveness improved${NC}"

# 10. Add useful bash aliases
echo -e "\n${YELLOW}Adding useful bash aliases...${NC}"
if [[ -n "$SUDO_USER" ]]; then
    SUDO_USER_HOME=$(eval echo ~${SUDO_USER})
    BASHRC="$SUDO_USER_HOME/.bashrc"
else
    BASHRC="/root/.bashrc"
fi

if ! grep -q "# Custom Aliases" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" << 'EOFALIASES'

# Custom Aliases
alias update='sudo pacman -Syu'
alias install='sudo pacman -S'
alias remove='sudo pacman -Rns'
alias search='pacman -Ss'
alias clean='sudo pacman -Sc && yay -Sc'
alias orphans='sudo pacman -Rns $(pacman -Qtdq)'
alias ll='ls -lah --color=auto'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias mirror='sudo reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist'
EOFALIASES
    echo -e "${GREEN}✓ Bash aliases added${NC}"
else
    echo -e "${GREEN}✓ Bash aliases already exist${NC}"
fi

# 11. Install reflector for automatic mirror updates
echo -e "\n${YELLOW}Setting up automatic mirror updates...${NC}"
pacman -S --needed --noconfirm reflector
cat > /etc/xdg/reflector/reflector.conf << 'EOFMIRROR'
--save /etc/pacman.d/mirrorlist
--protocol https
--country Nepal,India,Singapore,Taiwan,Japan,Germany,United Kingdom
--latest 20
--sort rate
EOFMIRROR
systemctl enable reflector.timer
echo -e "${GREEN}✓ Reflector configured${NC}"

# 12. Enable systemd-oomd (Out of Memory daemon)
echo -e "\n${YELLOW}Enabling OOM protection...${NC}"
systemctl enable --now systemd-oomd
echo -e "${GREEN}✓ OOM protection enabled${NC}"

# 13. Optimize makepkg for faster AUR builds
echo -e "\n${YELLOW}Optimizing makepkg...${NC}"
if [[ ! -f /etc/makepkg.conf.bak ]]; then
    cp /etc/makepkg.conf /etc/makepkg.conf.bak
fi
# Use all cores for compilation
CORES=$(nproc)
sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$CORES\"/" /etc/makepkg.conf
# Enable compression
sed -i 's/COMPRESSGZ=(gzip -c -f -n)/COMPRESSGZ=(pigz -c -f -n)/' /etc/makepkg.conf
sed -i 's/COMPRESSBZ2=(bzip2 -c -f)/COMPRESSBZ2=(pbzip2 -c -f)/' /etc/makepkg.conf
sed -i 's/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -z - --threads=0)/' /etc/makepkg.conf
echo -e "${GREEN}✓ Makepkg optimized for $CORES cores${NC}"

# 14. Set up paccache for automatic cache cleanup
echo -e "\n${YELLOW}Setting up automatic pacman cache cleanup...${NC}"
systemctl enable paccache.timer
echo -e "${GREEN}✓ Paccache timer enabled (keeps last 3 versions)${NC}"

# 15. Disable watchdog timers for faster boot
echo -e "\n${YELLOW}Disabling watchdog timers for faster boot...${NC}"
if [[ -f /etc/kernel/cmdline ]]; then
    if ! grep -q "nowatchdog" /etc/kernel/cmdline; then
        echo "$(cat /etc/kernel/cmdline) nowatchdog mitigations=off" > /etc/kernel/cmdline
        bootctl update 2>/dev/null || true
        echo -e "${GREEN}✓ Watchdog timers disabled${NC}"
    else
        echo -e "${GREEN}✓ Watchdog timers already disabled${NC}"
    fi
else
    echo -e "${YELLOW}⚠ /etc/kernel/cmdline not found, skipping${NC}"
fi

# 16. Optimize systemd journal for speed and size
echo -e "\n${YELLOW}Optimizing systemd journal for speed and size...${NC}"
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/size-limit.conf << 'EOFJOURNAL'
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=50M
Compress=yes
EOFJOURNAL
systemctl restart systemd-journald
echo -e "${GREEN}✓ Journal compression enabled and size limited${NC}"

# Final summary
echo -e "\n${GREEN}======================================${NC}"
echo -e "${GREEN}Additional Optimizations Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo -e "✓ TRIM enabled for SSDs"
echo -e "✓ Swappiness reduced to 10"
echo -e "✓ I/O schedulers optimized"
echo -e "✓ System responsiveness improved"
echo -e "✓ Useful bash aliases added"
echo -e "✓ Automatic mirror updates (reflector)"
echo -e "✓ OOM protection enabled"
echo -e "✓ Makepkg optimized for parallel builds"
echo -e "✓ Automatic cache cleanup enabled"
