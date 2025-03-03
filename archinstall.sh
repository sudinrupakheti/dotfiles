#!/usr/bin/env bash

# Colors for visibility
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
RED='\e[31m'
RESET='\e[0m'

# Function to check if a command succeeded
check_status() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: $1 failed!${RESET}"
        exit 1
    fi
}

# Function to print a breaker line
breaker() {
    echo -e "${BLUE}======================================${RESET}"
}

# Verify internet connection
breaker
echo -e "${BLUE}Checking internet connection...${RESET}"
ping -c 3 archlinux.org &>/dev/null || { echo -e "${RED}No internet connection. Exiting...${RESET}"; exit 1; }

# ASCII Art for Arch Linux Logo and Welcome Message
breaker
cat << "EOF"
                   -`
                 .o+`
                `ooo/
               `+oooo:
              `+oooooo:
              -+oooooo+:
            `/:-:++oooo+:
           `/++++/+++++++:
          `/++++++++++++++:
         `/+++ooooooooooooo/`
        ./ooosssso++osssssso+`
       .oossssso-````/ossssss+`
      -osssssso.      :ssssssso.
     :osssssss/        osssso+++.
    /ossssssss/        +ssssooo/-
  `/ossssso+/:-        -:/+osssso+-
 `+sso+:-`                 `.-/+oso:
`++:.                           `-/+/
.`                                 `
    Welcome to Arch Install!
EOF
echo -e "${GREEN}Let’s set up your Arch Linux system!${RESET}"
breaker

# User Input with Validation
while true; do
    echo -e "${YELLOW}Enter EFI partition:${RESET}"
    echo -e "${GREEN}Note: If this is a Windows EFI partition (vfat), it will NOT be formatted.${RESET}"
    echo -e "${RED}WARNING: Ensure this is the correct partition for dual-booting!${RESET}"
    read -r EFI
    [[ -b "$EFI" ]] && break
    echo -e "${RED}Invalid EFI partition. Try again.${RESET}"
done

while true; do
    echo -e "${YELLOW}Enter Root partition:${RESET}"
    read -r ROOT
    [[ -b "$ROOT" ]] && break
    echo -e "${RED}Invalid Root partition. Try again.${RESET}"
done

echo -e "${YELLOW}Choose filesystem for Root partition (ext4/btrfs):${RESET}"
read -r FS_TYPE
FS_TYPE=${FS_TYPE,,} # Convert to lowercase
[[ "$FS_TYPE" != "ext4" && "$FS_TYPE" != "btrfs" ]] && FS_TYPE="ext4"

echo -e "${YELLOW}Enable ZRAM instead of swap? (y/n)${RESET}"
read -r ZRAM_ENABLE
ZRAM_ENABLE=${ZRAM_ENABLE,,} # Convert to lowercase
[[ "$ZRAM_ENABLE" != "y" && "$ZRAM_ENABLE" != "n" ]] && ZRAM_ENABLE="n"

if [[ "$ZRAM_ENABLE" == "n" ]]; then
    echo -e "${YELLOW}Enter Swap partition (or leave empty to skip):${RESET}"
    read -r SWAP
    [[ -n "$SWAP" && ! -b "$SWAP" ]] && { echo -e "${RED}Invalid Swap partition! Exiting...${RESET}"; exit 1; }
fi

echo -e "${YELLOW}Detecting NVIDIA GPU...${RESET}"
if lspci | grep -i nvidia &>/dev/null; then
    echo -e "${GREEN}NVIDIA GPU detected! Install NVIDIA drivers? (y/n, recommended only for gaming/heavy GPU tasks)${RESET}"
    read -r NVIDIA_ENABLE
    NVIDIA_ENABLE=${NVIDIA_ENABLE,,}
    [[ "$NVIDIA_ENABLE" != "y" && "$NVIDIA_ENABLE" != "n" ]] && NVIDIA_ENABLE="n"
else
    echo -e "${YELLOW}No NVIDIA GPU detected.${RESET}"
    NVIDIA_ENABLE="n"
fi

echo -e "${YELLOW}Choose bootloader (grub/systemd-boot):${RESET}"
read -r BOOTLOADER
BOOTLOADER=${BOOTLOADER,,} # Convert to lowercase
[[ "$BOOTLOADER" != "grub" && "$BOOTLOADER" != "systemd-boot" ]] && BOOTLOADER="grub" # Default to grub if invalid

echo -e "${YELLOW}Enter your username:${RESET}"
read -r USERNAME
[[ -z "$USERNAME" ]] && { echo -e "${RED}Username cannot be empty! Exiting...${RESET}"; exit 1; }

echo -e "${YELLOW}Enter hostname (default: archlinux):${RESET}"
read -r HOSTNAME
HOSTNAME=${HOSTNAME:-archlinux}

echo -e "${YELLOW}Enter password for $USERNAME:${RESET}"
read -s USER_PASS
echo -e "\n${YELLOW}Confirm password:${RESET}"
read -s USER_PASS_CONFIRM
[[ "$USER_PASS" != "$USER_PASS_CONFIRM" ]] && { echo -e "${RED}Passwords do not match! Exiting...${RESET}"; exit 1; }

# Initialize package manager and mirrors
breaker
echo -e "${GREEN}Initializing package manager and updating mirrors...${RESET}"
pacman-key --init && pacman-key --populate
check_status "Pacman key initialization"
pacman -Sy reflector --noconfirm --needed
check_status "Reflector installation"
reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
check_status "Mirrorlist update"

# Format Partitions
breaker
echo -e "${GREEN}Formatting Partitions...${RESET}"
[[ "$(blkid -s TYPE -o value "$EFI")" != "vfat" ]] && mkfs.vfat -F32 "$EFI"
check_status "EFI formatting"
mkfs."$FS_TYPE" -F "$ROOT"
check_status "Root formatting"
[[ "$ZRAM_ENABLE" == "n" && -n "$SWAP" ]] && mkswap "$SWAP"
check_status "Swap formatting"

# Mount Partitions
breaker
echo -e "${GREEN}Mounting Partitions...${RESET}"
mount "$ROOT" /mnt
check_status "Root partition mounting"
if [[ "$BOOTLOADER" == "grub" ]]; then
    mount --mkdir "$EFI" /mnt/boot/efi
else  # systemd-boot
    mount --mkdir "$EFI" /mnt/boot
fi
check_status "EFI partition mounting"
[[ "$ZRAM_ENABLE" == "n" && -n "$SWAP" ]] && swapon "$SWAP"

# Configure pacman for parallel downloads
sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf

# Install Base System
breaker
echo -e "${GREEN}Installing Arch Linux Base System...${RESET}"
BASE_PKGS="base base-devel linux linux-firmware linux-headers nano networkmanager sudo git amd-ucode"
[[ "$FS_TYPE" == "btrfs" ]] && BASE_PKGS+=" btrfs-progs"
[[ "$NVIDIA_ENABLE" == "y" ]] && BASE_PKGS+=" nvidia nvidia-utils nvidia-settings lib32-nvidia-utils nvidia-prime"
[[ "$BOOTLOADER" == "grub" ]] && BASE_PKGS+=" grub efibootmgr os-prober"
pacstrap /mnt $BASE_PKGS --noconfirm --needed
check_status "Base system installation"

genfstab -U /mnt >> /mnt/etc/fstab
check_status "Fstab generation"

# Post-Install Configuration
breaker
echo -e "${GREEN}Configuring Your System...${RESET}"
cat <<EOF > /mnt/root/post-install.sh
#!/usr/bin/env bash

# User setup
useradd -m "$USERNAME"
usermod -aG wheel,storage,power,audio,video "$USERNAME"
echo "$USERNAME:$USER_PASS" | chpasswd

# Sudo setup
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers

# Language and Locale
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Timezone and NTP
ln -sf /usr/share/zoneinfo/Asia/Kathmandu /etc/localtime
hwclock --systohc
systemctl enable systemd-timesyncd
systemctl start systemd-timesyncd

# Hostname
echo "$HOSTNAME" > /etc/hostname
cat <<HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain   $HOSTNAME
HOSTS

# ZRAM setup
if [[ "$ZRAM_ENABLE" == "y" ]]; then
    pacman -S systemd-zram-generator --noconfirm --needed
    echo -e "[zram0]\nzram-size = ram / 2\ncompression-algorithm = zstd" > /etc/systemd/zram-generator.conf
    systemctl enable systemd-zram-setup@zram0
fi

# Bootloader setup
if [[ "$BOOTLOADER" == "grub" ]]; then
    echo "Installing GRUB..."
    echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash iommu=soft amdgpu.dc=0"' >> /etc/default/grub
    [[ "$NVIDIA_ENABLE" == "y" ]] && echo "nvidia-drm.modeset=1" >> /etc/default/grub
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ArchLinux
    grub-mkconfig -o /boot/grub/grub.cfg
else  # systemd-boot
    echo "Installing systemd-boot..."
    bootctl --path=/boot install
    mkdir -p /boot/loader/entries
    cat <<ARCH > /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options root=PARTUUID=$(blkid -s PARTUUID -o value "$ROOT") rw quiet splash iommu=soft amdgpu.dc=0
[[ "$NVIDIA_ENABLE" == "y" ]] && echo "nvidia-drm.modeset=1" >> /boot/loader/entries/arch.conf
ARCH
    cat <<WIN > /boot/loader/entries/windows.conf
title   Windows
efi     /EFI/Microsoft/Boot/bootmgfw.efi
WIN
    cat <<LOADER > /boot/loader/loader.conf
default arch.conf
timeout 5
editor  no
LOADER
fi

# Install additional services and power management
pacman -S networkmanager bluez pipewire pipewire-alsa pipewire-pulse wireplumber tlp --noconfirm --needed
[[ "$NVIDIA_ENABLE" == "y" ]] && pacman -S nvidia-prime --noconfirm --needed

# Enable services
systemctl enable NetworkManager bluetooth pipewire pipewire-pulse tlp systemd-timesyncd

# Configure TLP for battery optimization
cat <<TLP > /etc/tlp.conf
TLP_ENABLE=1
CPU_SCALING_GOVERNOR_ON_AC=performance
CPU_SCALING_GOVERNOR_ON_BAT=powersave
CPU_ENERGY_PERF_POLICY_ON_AC=performance
CPU_ENERGY_PERF_POLICY_ON_BAT=power
CPU_BOOST_ON_AC=1
CPU_BOOST_ON_BAT=0
PLATFORM_PROFILE_ON_AC=performance
PLATFORM_PROFILE_ON_BAT=low
TLP_DEFAULT_MODE=BAT
TLP_PERSISTENT_DEFAULT=1
RUNTIME_PM_ON_BAT=auto
# Disable NVIDIA GPU if present but not enabled
[[ "$NVIDIA_ENABLE" == "n" ]] && echo "DEVICES_TO_DISABLE_ON_STARTUP=\"nvidia\"" >> /etc/tlp.conf
TLP

# Install yay (AUR helper)
echo "Setting up yay AUR helper..."
pacman -S base-devel git --noconfirm --needed
sudo -u "$USERNAME" bash <<YAY
cd /home/$USERNAME
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si --noconfirm
rm -rf yay-bin
YAY

# Configure switchable graphics for NVIDIA (only if enabled)
if [[ "$NVIDIA_ENABLE" == "y" ]]; then
    echo -e "#!/bin/bash\nprime-run \"\$@\"" > /usr/local/bin/nvidia-run
    chmod +x /usr/local/bin/nvidia-run
    echo "To use NVIDIA GPU, run applications with 'nvidia-run' (e.g., 'nvidia-run glxinfo')"
else
    # Ensure NVIDIA GPU is off if present
    if lspci | grep -i nvidia &>/dev/null; then
        echo "Disabling NVIDIA GPU for power saving..."
    fi
fi

echo "Arch Linux setup complete! Reboot now."
EOF

chmod +x /mnt/root/post-install.sh
arch-chroot /mnt bash /root/post-install.sh
check_status "Final setup"

# Cleanup
rm /mnt/root/post-install.sh

breaker
echo -e "${GREEN}Installation complete! Type 'reboot' to start your new Arch Linux.${RESET}"
[[ "$NVIDIA_ENABLE" == "y" ]] && echo -e "${YELLOW}Note: Use 'nvidia-run <application>' to run programs with NVIDIA GPU${RESET}"
echo -e "${GREEN}AUR is ready with 'yay'. Install packages with 'yay -S <package>'${RESET}"
breaker
