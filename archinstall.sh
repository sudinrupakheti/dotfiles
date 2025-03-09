#!/usr/bin/env bash

# Colors for a pretty interface
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
RED='\e[31m'
CYAN='\e[36m'
MAGENTA='\e[35m'
BOLD='\e[1m'
RESET='\e[0m'

# Function to check if a command succeeded
check_status() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}${BOLD}Error: $1 failed!${RESET}"
        exit 1
    else
        echo -e "${GREEN}✓ $1 completed successfully${RESET}"
    fi
}

# Function to print a breaker line
breaker() {
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${RESET}"
}

# Function to show a spinner for long operations
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep -w $pid)" ]; do
        local temp=${spinstr#?}
        printf "${CYAN} [%c]  ${RESET}" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Improved ASCII Art Welcome Message
clear
breaker
cat << "EOF"
      ____          __  __     
     /    \________/  \/  \    
    /                     /    
   |  ARCH LINUX INSTALL |     
    \                   /      
     \_________________/       
            |  |              
         ___/  \___          
╭───────────────────────────────╮
│     MINIMAL INSTALLATION      │
╰───────────────────────────────╯
EOF
echo -e "${GREEN}${BOLD}Let's set up your Arch Linux system!${RESET}"
breaker

# Verify internet connection
echo -e "${BLUE}${BOLD}Checking internet connection...${RESET}"
if ping -c 3 archlinux.org &>/dev/null; then
    echo -e "${GREEN}✓ Internet connection available${RESET}"
else
    echo -e "${RED}${BOLD}No internet connection. Exiting...${RESET}"
    exit 1
fi

# Function to select a partition from available devices
select_partition() {
    local prompt="$1"
    local allow_skip="$2"
    
    echo -e "\n${CYAN}${BOLD}=== Current Disk Layout ===${RESET}"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE
    echo -e "${CYAN}${BOLD}=========================${RESET}\n"
    
    local partitions=($(lsblk -ln -o NAME,TYPE | grep 'part' | awk '{print "/dev/"$1}'))
    if [ ${#partitions[@]} -eq 0 ]; then
        echo -e "${RED}${BOLD}No partitions found! Exiting...${RESET}"
        exit 1
    fi
    echo -e "${YELLOW}${BOLD}$prompt${RESET}"
    for i in "${!partitions[@]}"; do
        local size=$(lsblk -n -o SIZE "${partitions[$i]}")
        local fstype=$(lsblk -n -o FSTYPE "${partitions[$i]}")
        local mountpoint=$(lsblk -n -o MOUNTPOINT "${partitions[$i]}")
        echo -e "${BLUE}$((i+1)). ${partitions[$i]} (${CYAN}Size: $size${BLUE}, ${CYAN}Type: ${fstype:-None}${BLUE}, ${CYAN}Mounted: ${mountpoint:-No}${BLUE})${RESET}"
    done
    while true; do
        read -p "Enter number (1-${#partitions[@]}${allow_skip:+, 0 to skip}): " choice
        if [[ "$allow_skip" && "$choice" == "0" ]]; then
            echo ""
            return
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#partitions[@]}" ]; then
            echo "${partitions[$((choice-1))]}"
            return
        fi
        echo -e "${RED}Invalid choice. Try again.${RESET}"
    done
}

# Check if system is UEFI
if [ -d "/sys/firmware/efi/efivars" ]; then
    echo -e "${GREEN}✓ UEFI system detected${RESET}"
else
    echo -e "${RED}${BOLD}This script requires a UEFI system. Exiting...${RESET}"
    exit 1
fi

# Check for AMD CPU
if grep -q "AMD" /proc/cpuinfo; then
    AMD_CPU=true
    echo -e "${GREEN}✓ AMD CPU detected${RESET}"
else
    AMD_CPU=false
    echo -e "${YELLOW}Non-AMD CPU detected${RESET}"
fi

# Partition Selection
breaker
echo -e "${GREEN}${BOLD}Select your partitions:${RESET}"
EFI=$(select_partition "Choose EFI partition (usually ~300M-1G, vfat for dual-boot):")
ROOT=$(select_partition "Choose Root partition (where Arch will be installed):")
SWAP=$(select_partition "Choose Swap partition (optional):" "yes")
if [ -n "$SWAP" ]; then
    SWAP_ENABLED=true
    echo -e "${GREEN}✓ Swap partition selected: $SWAP${RESET}"
else
    SWAP_ENABLED=false
    echo -e "${YELLOW}No swap partition selected${RESET}"
fi

# Filesystem Selection
breaker
echo -e "${YELLOW}${BOLD}Choose filesystem for Root partition:${RESET}"
echo -e "${BLUE}1. ext4 ${CYAN}(Stable, widely used)${RESET}"
echo -e "${BLUE}2. btrfs ${CYAN}(Advanced features like snapshots)${RESET}"
while true; do
    read -p "Enter number (1-2, default 1): " FS_CHOICE
    case "$FS_CHOICE" in
        1|"") FS_TYPE="ext4"; break;;
        2) FS_TYPE="btrfs"; break;;
        *) echo -e "${RED}Invalid choice. Try again.${RESET}";;
    esac
done
echo -e "${GREEN}✓ Selected filesystem: $FS_TYPE${RESET}"

# Bootloader Selection
breaker
echo -e "${YELLOW}${BOLD}Choose bootloader:${RESET}"
echo -e "${BLUE}1. GRUB ${CYAN}(Feature-rich, supports dual-boot)${RESET}"
echo -e "${BLUE}2. systemd-boot ${CYAN}(Lightweight, simple)${RESET}"
while true; do
    read -p "Enter number (1-2, default 1): " BOOT_CHOICE
    case "$BOOT_CHOICE" in
        1|"") BOOTLOADER="grub"; break;;
        2) BOOTLOADER="systemd-boot"; break;;
        *) echo -e "${RED}Invalid choice. Try again.${RESET}";;
    esac
done
echo -e "${GREEN}✓ Selected bootloader: $BOOTLOADER${RESET}"

# User and Root Configuration
breaker
echo -e "${GREEN}${BOLD}Set up user and root accounts:${RESET}"
while true; do
    read -p "${YELLOW}Enter your username:${RESET} " USERNAME
    if [[ -n "$USERNAME" && "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        break
    fi
    echo -e "${RED}Invalid username! Use only lowercase letters, numbers, underscores, and hyphens.${RESET}"
done

echo -e "${YELLOW}Enter password for $USERNAME:${RESET}"
read -s USER_PASS
echo -e "\n${YELLOW}Confirm password:${RESET}"
read -s USER_PASS_CONFIRM
[[ "$USER_PASS" != "$USER_PASS_CONFIRM" ]] && { echo -e "${RED}${BOLD}Passwords do not match! Exiting...${RESET}"; exit 1; }

while true; do
    read -p "${YELLOW}Enter root username (default: root):${RESET} " ROOT_NAME
    ROOT_NAME=${ROOT_NAME:-root}
    [[ -n "$ROOT_NAME" ]] && break
    echo -e "${RED}Root name cannot be empty!${RESET}"
done

echo -e "${YELLOW}Enter password for $ROOT_NAME:${RESET}"
read -s ROOT_PASS
echo -e "\n${YELLOW}Confirm password:${RESET}"
read -s ROOT_PASS_CONFIRM
[[ "$ROOT_PASS" != "$ROOT_PASS_CONFIRM" ]] && { echo -e "${RED}${BOLD}Passwords do not match! Exiting...${RESET}"; exit 1; }

# Hostname
breaker
echo -e "${YELLOW}${BOLD}Enter hostname (default: archlinux):${RESET}"
read -r HOSTNAME
HOSTNAME=${HOSTNAME:-archlinux}
echo -e "${GREEN}✓ Hostname set to: $HOSTNAME${RESET}"

# Kernel Selection
breaker
echo -e "${YELLOW}${BOLD}Choose kernel:${RESET}"
echo -e "${BLUE}1. linux ${CYAN}(Default kernel)${RESET}"
echo -e "${BLUE}2. linux-lts ${CYAN}(Long-term support kernel)${RESET}"
echo -e "${BLUE}3. linux-zen ${CYAN}(Optimized for desktop usage)${RESET}"
while true; do
    read -p "Enter number (1-3, default 1): " KERNEL_CHOICE
    case "$KERNEL_CHOICE" in
        1|"") KERNEL="linux"; break;;
        2) KERNEL="linux-lts"; break;;
        3) KERNEL="linux-zen"; break;;
        *) echo -e "${RED}Invalid choice. Try again.${RESET}";;
    esac
done
echo -e "${GREEN}✓ Selected kernel: $KERNEL${RESET}"

# Update Reflector and Pacman
breaker
echo -e "${GREEN}${BOLD}Updating mirrors and enabling parallel downloads...${RESET}"
(pacman -Sy reflector --noconfirm --needed) & spinner $!
check_status "Reflector installation"
echo -e "${CYAN}Finding fastest mirrors...${RESET}"
(reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist) & spinner $!
check_status "Mirrorlist update"
sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
sed -i 's/#Color/Color/' /etc/pacman.conf
check_status "Pacman configuration"

# Format Partitions
breaker
echo -e "${GREEN}${BOLD}Formatting partitions...${RESET}"
if [[ "$(blkid -s TYPE -o value "$EFI")" != "vfat" ]]; then
    echo -e "${YELLOW}EFI partition is not vfat. Formatting as vfat...${RESET}"
    (mkfs.vfat -F32 "$EFI") & spinner $!
    check_status "EFI formatting"
else
    echo -e "${GREEN}✓ EFI partition is already vfat, skipping format...${RESET}"
fi

echo -e "${YELLOW}Formatting $ROOT as $FS_TYPE...${RESET}"
if [[ "$FS_TYPE" == "btrfs" ]]; then
    (mkfs.btrfs -f -L ROOT "$ROOT") & spinner $!
    check_status "Root formatting (btrfs)"
else
    (mkfs.ext4 -F -L ROOT "$ROOT") & spinner $!
    check_status "Root formatting (ext4)"
fi

if [[ -n "$SWAP" ]]; then
    echo -e "${YELLOW}Formatting and enabling swap...${RESET}"
    (mkswap -L SWAP "$SWAP") & spinner $!
    check_status "Swap formatting"
    swapon "$SWAP"
    check_status "Swap activation"
fi

# Mount Partitions with proper BTRFS subvolumes
breaker
echo -e "${GREEN}${BOLD}Mounting partitions...${RESET}"
if [[ "$FS_TYPE" == "btrfs" ]]; then
    mount "$ROOT" /mnt
    check_status "Initial root mounting"
    
    echo -e "${CYAN}Creating BTRFS subvolumes...${RESET}"
    btrfs subvolume create /mnt/@ 
    check_status "@ subvolume creation"
    btrfs subvolume create /mnt/@home
    check_status "@home subvolume creation" 
    btrfs subvolume create /mnt/@var
    check_status "@var subvolume creation"
    btrfs subvolume create /mnt/@snapshots
    check_status "@snapshots subvolume creation"
    
    umount /mnt
    
    mount -o noatime,compress=zstd,space_cache=v2,subvol=@ "$ROOT" /mnt
    check_status "@ subvolume mounting"
    
    mkdir -p /mnt/{home,var,boot,.snapshots}
    
    mount -o noatime,compress=zstd,space_cache=v2,subvol=@home "$ROOT" /mnt/home
    check_status "@home subvolume mounting"
    mount -o noatime,compress=zstd,space_cache=v2,subvol=@var "$ROOT" /mnt/var
    check_status "@var subvolume mounting"
    mount -o noatime,compress=zstd,space_cache=v2,subvol=@snapshots "$ROOT" /mnt/.snapshots
    check_status "@snapshots subvolume mounting"
else
    mount "$ROOT" /mnt
    check_status "Root mounting"
fi

if [[ "$BOOTLOADER" == "grub" ]]; then
    mkdir -p /mnt/boot/efi
    mount "$EFI" /mnt/boot/efi
    check_status "EFI mounting for GRUB"
else
    mkdir -p /mnt/boot
    mount "$EFI" /mnt/boot
    check_status "EFI mounting for systemd-boot"
fi

# Install Base System
breaker
echo -e "${GREEN}${BOLD}Installing base system...${RESET}"
BASE_PKGS="base base-devel $KERNEL ${KERNEL}-headers linux-firmware networkmanager sudo pacman-contrib"
[[ "$FS_TYPE" == "btrfs" ]] && BASE_PKGS+=" btrfs-progs"
[[ "$BOOTLOADER" == "grub" ]] && BASE_PKGS+=" grub efibootmgr"
[[ "$AMD_CPU" == true ]] && BASE_PKGS+=" amd-ucode" || BASE_PKGS+=" intel-ucode"
BASE_PKGS+=" vim nano git wget curl"

echo -e "${CYAN}Installing packages:${RESET} $BASE_PKGS"
(pacstrap /mnt $BASE_PKGS --noconfirm --needed) & pid=$!
spinner $pid
check_status "Base system installation"

echo -e "${CYAN}Generating fstab...${RESET}"
(genfstab -U /mnt >> /mnt/etc/fstab) & spinner $!
check_status "Fstab generation"

if [[ "$SWAP_ENABLED" == true ]]; then
    echo -e "${CYAN}Configuring hibernation support...${RESET}"
    SWAP_UUID=$(blkid -s UUID -o value "$SWAP")
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems resume fsck)/' /mnt/etc/mkinitcpio.conf
fi

# Post-Install Configuration
breaker
echo -e "${GREEN}${BOLD}Configuring system...${RESET}"
cat <<EOF > /mnt/root/post-install.sh
#!/usr/bin/env bash

GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
RED='\e[31m'
CYAN='\e[36m'
BOLD='\e[1m'
RESET='\e[0m'

echo -e "\${GREEN}\${BOLD}Starting post-installation configuration...\${RESET}"

echo -e "\${CYAN}Creating user accounts...\${RESET}"
useradd -m "$USERNAME"
echo "$USERNAME:$USER_PASS" | chpasswd
usermod -aG wheel "$USERNAME"
echo "$ROOT_NAME:$ROOT_PASS" | chpasswd

echo -e "\${CYAN}Configuring sudo...\${RESET}"
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

echo -e "\${CYAN}Setting up locale and timezone...\${RESET}"
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
ln -sf /usr/share/zoneinfo/Asia/Kathmandu /etc/localtime
hwclock --systohc

echo -e "\${CYAN}Setting hostname...\${RESET}"
echo "$HOSTNAME" > /etc/hostname
cat <<HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain   $HOSTNAME
HOSTS

if [ -d "/sys/block/$(basename $ROOT | sed 's/[0-9]*//g')/queue/rotational" ]; then
    if [ "\$(cat /sys/block/$(basename $ROOT | sed 's/[0-9]*//g')/queue/rotational)" -eq 0 ]; then
        echo -e "\${CYAN}SSD detected - enabling TRIM...\${RESET}"
        mkdir -p /etc/systemd/system/fstrim.timer.d
        cat <<TRIM > /etc/systemd/system/fstrim.timer.d/override.conf
[Timer]
OnCalendar=
OnCalendar=weekly
TRIM
        systemctl enable fstrim.timer
    fi
fi

echo -e "\${CYAN}Installing bootloader...\${RESET}"
if [[ "$BOOTLOADER" == "grub" ]]; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ArchLinux
    if [[ "$HIBERNATE_ENABLED" == "true" ]]; then
        echo -e "\${CYAN}Configuring hibernation support in GRUB...\${RESET}"
        sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT/ s/"$/ resume=UUID=$SWAP_UUID"/' /etc/default/grub
    fi
    grub-mkconfig -o /boot/grub/grub.cfg
else
    bootctl --path=/boot install
    cat <<LOADER > /boot/loader/loader.conf
default arch.conf
timeout 5
editor no
LOADER
    cat <<ENTRY > /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-$KERNEL
initrd  /$( [ "$AMD_CPU" == "true" ] && echo "amd" || echo "intel" )-ucode.img
initrd  /initramfs-$KERNEL.img
options root=PARTUUID=$(blkid -s PARTUUID -o value "$ROOT") $(echo "$FS_TYPE" | grep -q "btrfs" && echo "rootflags=subvol=@") rw
ENTRY
    if [[ "$HIBERNATE_ENABLED" == "true" ]]; then
        echo -e "\${CYAN}Configuring hibernation support in systemd-boot...\${RESET}"
        sed -i "/^options/ s/\$/ resume=UUID=$SWAP_UUID/" /boot/loader/entries/arch.conf
    fi
fi

if [[ "$SWAP_ENABLED" == "true" ]]; then
    echo -e "\${CYAN}Regenerating initramfs for hibernation...\${RESET}"
    mkinitcpio -P
fi

echo -e "\${CYAN}Enabling essential services...\${RESET}"
systemctl enable NetworkManager

echo -e "\${CYAN}Installing YAY AUR helper...\${RESET}"
pacman -S --noconfirm base-devel
su - $USERNAME -c "cd /tmp && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si --noconfirm"

echo -e "\${CYAN}Setting up pacman hooks...\${RESET}"
mkdir -p /etc/pacman.d/hooks
cat <<PACCACHE > /etc/pacman.d/hooks/clean_package_cache.hook
[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Package
Target = *

[Action]
Description = Cleaning pacman cache...
When = PostTransaction
Exec = /usr/bin/paccache -r
PACCACHE

if [[ "$FS_TYPE" == "btrfs" ]]; then
    echo -e "\${CYAN}Setting up Snapper for BTRFS snapshots...\${RESET}"
    pacman -S --noconfirm snapper
    snapper -c root create-config /
    systemctl enable snapper-timeline.timer
    systemctl enable snapper-cleanup.timer
fi

echo -e "\${GREEN}\${BOLD}Setup complete! Reboot to start using your new Arch Linux system.\${RESET}"
EOF

chmod +x /mnt/root/post-install.sh
echo -e "${CYAN}Running post-installation script...${RESET}"
(arch-chroot /mnt bash /root/post-install.sh) & pid=$!
spinner $pid
check_status "System configuration"
rm /mnt/root/post-install.sh

# Finish
breaker
cat << "EOF"
                 .
                 |
          .     |     ,
           \  __|__  /
         -- \_`   `_/ --
         |  |  ⌄  ⌄  |  |
             _\___/_
            /       \
           /         \
     ____ /           \ ____
    /                       \
   /    ARCH INSTALLATION    \
  /     COMPLETE. ENJOY!      \
 /                             \
/______________________________\
EOF
echo -e "${GREEN}${BOLD}Installation complete! Type 'reboot' to start your Arch Linux system.${RESET}"
breaker

echo -e "${CYAN}${BOLD}Installation Summary:${RESET}"
echo -e "${YELLOW}• Filesystem:${RESET} $FS_TYPE"
echo -e "${YELLOW}• Bootloader:${RESET} $BOOTLOADER"
echo -e "${YELLOW}• Kernel:${RESET} $KERNEL"
echo -e "${YELLOW}• Username:${RESET} $USERNAME"
echo -e "${YELLOW}• Hostname:${RESET} $HOSTNAME"
echo -e "${YELLOW}• AMD CPU Support:${RESET} $([ "$AMD_CPU" == "true" ] && echo "Yes" || echo "No")"
echo -e "${YELLOW}• Hibernation Support:${RESET} $([ "$SWAP_ENABLED" == "true" ] && echo "Yes" || echo "No")"
echo -e "${YELLOW}• BTRFS Subvolumes:${RESET} $([ "$FS_TYPE" == "btrfs" ] && echo "@, @home, @var, @snapshots" || echo "N/A")"
echo -e "${YELLOW}• AUR Helper:${RESET} YAY"
breaker
