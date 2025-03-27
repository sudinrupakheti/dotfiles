#!/usr/bin/env bash

# Colors for UI
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
RED='\e[31m'
CYAN='\e[36m'
BOLD='\e[1m'
RESET='\e[0m'

# Function to check command status
check_status() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}${BOLD}Error: $1 failed!${RESET}"
        exit 1
    else
        echo -e "${GREEN}✓ $1 completed successfully${RESET}"
    fi
}

# Spinner for long operations
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

# Breaker line
breaker() {
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${RESET}"
}

# Welcome message with your ASCII logo
clear
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
   ARCH LINUX INSTALL
EOF
echo -e "${GREEN}${BOLD}Minimal Arch Setup - Let's Begin!${RESET}"
breaker

# Partition selection function
select_partition() {
    local prompt="$1"
    local partitions=($(lsblk -ln -o NAME,TYPE | grep 'part' | awk '{print "/dev/"$1}'))
    if [ ${#partitions[@]} -eq 0 ]; then
        echo -e "${RED}${BOLD}No partitions found! Exiting...${RESET}"
        exit 1
    fi

    echo -e "\n${CYAN}${BOLD}=== Available Partitions ===${RESET}"
    lsblk -o NAME,SIZE,FSTYPE
    echo -e "${CYAN}${BOLD}===========================${RESET}"
    echo -e "${YELLOW}${BOLD}$prompt${RESET}"
    for i in "${!partitions[@]}"; do
        local size=$(lsblk -n -o SIZE "${partitions[$i]}")
        local fstype=$(lsblk -n -o FSTYPE "${partitions[$i]}")
        echo -e "${BLUE}$((i+1)). ${partitions[$i]} (${CYAN}Size: $size${BLUE}, ${CYAN}Type: ${fstype:-None}${BLUE})${RESET}"
    done

    while true; do
        read -p "Enter number (1-${#partitions[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#partitions[@]}" ]; then
            echo "${partitions[$((choice-1))]}"
            return
        fi
        echo -e "${RED}Invalid choice. Try again.${RESET}"
    done
}

# Partition setup
breaker
echo -e "${GREEN}${BOLD}Partition Setup:${RESET}"

# EFI Partition
echo -e "${YELLOW}EFI Partition Setup:${RESET}"
read -p "Use existing EFI partition or create a new one? (e/n): " EFI_CHOICE
if [[ "$EFI_CHOICE" == "e" || "$EFI_CHOICE" == "E" ]]; then
    EFI=$(select_partition "Select your existing EFI partition:")
    echo -e "${GREEN}✓ Using existing EFI: $EFI${RESET}"
else
    EFI=$(select_partition "Select partition to format as new EFI:")
    echo -e "${YELLOW}Formatting $EFI as vfat...${RESET}"
    (mkfs.vfat -F32 "$EFI") & spinner $!
    check_status "EFI formatting"
fi

# Swap Partition
echo -e "${YELLOW}Swap Partition Setup:${RESET}"
read -p "Do you want to set up a swap partition? (y/n): " SWAP_CHOICE
if [[ "$SWAP_CHOICE" == "y" || "$SWAP_CHOICE" == "Y" ]]; then
    SWAP=$(select_partition "Select partition for swap:")
    echo -e "${YELLOW}Formatting $SWAP as swap...${RESET}"
    (mkswap "$SWAP") & spinner $!
    check_status "Swap formatting"
    swapon "$SWAP"
    check_status "Swap activation"
    SWAP_ENABLED=true
else
    echo -e "${GREEN}✓ No swap partition selected (ZRAM will be used instead).${RESET}"
    SWAP_ENABLED=false
fi

# Root Partition
echo -e "${YELLOW}Root Partition Setup:${RESET}"
ROOT=$(select_partition "Select partition for root filesystem:")
echo -e "${YELLOW}Formatting $ROOT as ext4...${RESET}"
(mkfs.ext4 -F "$ROOT") & spinner $!
check_status "Root formatting"

# Mount partitions
breaker
echo -e "${GREEN}${BOLD}Mounting Partitions:${RESET}"
mount "$ROOT" /mnt
check_status "Root mounting"
mkdir -p /mnt/boot/efi
mount "$EFI" /mnt/boot/efi
check_status "EFI mounting"

# Mirror update and pacman config
breaker
echo -e "${GREEN}${BOLD}Updating Mirrors and Configuring Pacman:${RESET}"
(pacman -Sy reflector --noconfirm) & spinner $!
check_status "Reflector installation"
(reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist) & spinner $!
check_status "Mirrorlist update"
sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
check_status "Pacman parallel downloads enabled"
echo -e "${YELLOW}Setting up progress bar for pacman...${RESET}"
echo "XferCommand = /usr/bin/axel -n 16 -o %o %u" >> /etc/pacman.conf
check_status "Pacman progress bar setup"

# Package installation
breaker
echo -e "${GREEN}${BOLD}Installing Base System:${RESET}"
BASE_PKGS="base base-devel linux linux-firmware grub efibootmgr networkmanager os-prober git nano bluez pipewire pipewire-alsa pipewire-pulse pipewire-jack amd-ucode mesa bash-completion btop sudo timeshift zram-generator fastfetch wget curl zip unzip tar tlp cpufrequtils axel"
echo -e "${YELLOW}NVIDIA Driver Option:${RESET}"
read -p "Install NVIDIA driver? (y/n): " NVIDIA_CHOICE
if [[ "$NVIDIA_CHOICE" == "y" || "$NVIDIA_CHOICE" == "Y" ]]; then
    BASE_PKGS="$BASE_PKGS nvidia nvidia-utils"
fi
(pacstrap /mnt $BASE_PKGS --noconfirm) & pid=$!
spinner $pid
check_status "Base system installation"

# Generate fstab
breaker
echo -e "${GREEN}${BOLD}Generating fstab:${RESET}"
(genfstab -U /mnt >> /mnt/etc/fstab) & spinner $!
check_status "Fstab generation"

# User configuration
breaker
echo -e "${GREEN}${BOLD}User Configuration:${RESET}"
while true; do
    read -p "${YELLOW}Enter username:${RESET} " USERNAME
    if [[ -n "$USERNAME" && "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        break
    fi
    echo -e "${RED}Invalid username! Use lowercase, numbers, underscores, hyphens.${RESET}"
done
echo -e "${YELLOW}Enter password for $USERNAME:${RESET}"
read -s USER_PASS
echo -e "\n${YELLOW}Confirm password:${RESET}"
read -s USER_PASS_CONFIRM
[[ "$USER_PASS" != "$USER_PASS_CONFIRM" ]] && { echo -e "${RED}${BOLD}Passwords do not match! Exiting...${RESET}"; exit 1; }

echo -e "${YELLOW}Enter root password:${RESET}"
read -s ROOT_PASS
echo -e "\n${YELLOW}Confirm password:${RESET}"
read -s ROOT_PASS_CONFIRM
[[ "$ROOT_PASS" != "$ROOT_PASS_CONFIRM" ]] && { echo -e "${RED}${BOLD}Passwords do not match! Exiting...${RESET}"; exit 1; }

echo -e "${YELLOW}Enter hostname (default: archlinux):${RESET}"
read -r HOSTNAME
HOSTNAME=${HOSTNAME:-archlinux}

# Post-installation script
breaker
echo -e "${GREEN}${BOLD}Configuring System:${RESET}"
cat <<EOF > /mnt/root/post-install.sh
#!/usr/bin/env bash
GREEN='\e[32m'
YELLOW='\e[33m'
RED='\e[31m'
BOLD='\e[1m'
RESET='\e[0m'

echo -e "\${GREEN}\${BOLD}PostWESTInstallation Setup...\${RESET}"

# User setup
useradd -m "$USERNAME"
echo "$USERNAME:$USER_PASS" | chpasswd
usermod -aG wheel "$USERNAME"
echo "root:$ROOT_PASS" | chpasswd

# Sudo config
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers
echo "Defaults pwfeedback" >> /etc/sudoers

# Locale and timezone
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
ln -sf /usr/share/zoneinfo/Asia/Kathmandu /etc/localtime
hwclock --systohc
timedatectl set-ntp true
systemctl enable --now systemd-timesyncd

# Hostname
echo "$HOSTNAME" > /etc/hostname
cat <<HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain   $HOSTNAME
HOSTS

# Bootloader
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck
if [ "$SWAP_ENABLED" = true ]; then
    SWAP_UUID=\$(blkid -s UUID -o value "$SWAP")
    sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT/ s/"$/ resume=UUID=\$SWAP_UUID"/' /etc/default/grub
fi
grub-mkconfig -o /boot/grub/grub.cfg

# Initramfs
if [ "$SWAP_ENABLED" = true ]; then
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block filesystems fsck resume)/' /etc/mkinitcpio.conf
else
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block filesystems fsck)/' /etc/mkinitcpio.conf
fi
mkinitcpio -P

# ZRAM setup
cat <<ZRAM > /etc/systemd/zram-generator.conf
[zram0]
zram-size = 8192
compression-algorithm = zstd
ZRAM
systemctl enable systemd-zram-setup@zram0.service

# TRIM
systemctl enable fstrim.timer

# System optimizations
pacman -Rns \$(pacman -Qdtq) --noconfirm 2>/dev/null || true
pacman -Scc --noconfirm
pacman -S --needed tlp --noconfirm
systemctl enable --now tlp
pacman -S --needed cpufrequtils --noconfirm
echo "GOVERNOR=performance" > /etc/default/cpufreq
systemctl enable --now cpufreq.service

# Yay installation
su - "$USERNAME" -c "cd /tmp && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si --noconfirm"

# Services
systemctl enable NetworkManager bluetooth.service pipewire pipewire-pulse wireplumber systemd-zram-setup@zram0.service systemd-timesyncd tlp cpufreq.service

# Wi-Fi setup
echo -e "\${YELLOW}Configure Wi-Fi now? (y/n/skip):${RESET}"
read -p "" WIFI_CHOICE
if [[ "\$WIFI_CHOICE" == "y" || "\$WIFI_CHOICE" == "Y" ]]; then
    echo -e "\${YELLOW}Enter SSID:${RESET}"
    read -r SSID
    echo -e "\${YELLOW}Enter password:${RESET}"
    read -s WIFI_PASS
    nmcli dev wifi connect "\$SSID" password "\$WIFI_PASS"
fi

echo -e "\${GREEN}\${BOLD}Post-Installation Complete!${RESET}"
EOF

chmod +x /mnt/root/post-install.sh
(arch-chroot /mnt bash /root/post-install.sh) & pid=$!
spinner $pid
check_status "Post-installation"
rm /mnt/root/post-install.sh

# Completion message
breaker
cat << "EOF"
       .--.            
      /   _`.          
     _) ( )  `.        
    /  _ _ `.  _`.      
   /   )  )  )    )     
  )   /  /  /    /      
 /   /  /  /    /        
)   )  )  )    )        
 /    /   /    /         
 `._ _ _ _ _ _.'          
    `"`"`"`"`"`           
   SETUP COMPLETE!       
EOF
echo -e "${GREEN}${BOLD}Installation Done! Type 'reboot' to start your Arch system.${RESET}"
breaker
