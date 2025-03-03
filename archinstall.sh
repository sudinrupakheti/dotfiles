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
FS_TYPE=${FS_TYPE,,}
[[ "$FS_TYPE" != "ext4" && "$FS_TYPE" != "btrfs" ]] && FS_TYPE="ext4"

# Format Partitions
breaker
echo -e "${GREEN}Formatting Partitions...${RESET}"

umount "$ROOT" &>/dev/null
wipefs --all "$ROOT"

if [[ "$FS_TYPE" == "btrfs" ]]; then
    pacman -Sy btrfs-progs --noconfirm --needed
    mkfs.btrfs -f "$ROOT"
else
    mkfs.ext4 -F "$ROOT"
fi
check_status "Root partition formatting"

# Mount Partitions
breaker
echo -e "${GREEN}Mounting Partitions...${RESET}"
mount "$ROOT" /mnt
check_status "Root partition mounting"

mount --mkdir "$EFI" /mnt/boot/efi
check_status "EFI partition mounting"

# Configure pacman for parallel downloads
sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf

# Install Base System
breaker
echo -e "${GREEN}Installing Arch Linux Base System...${RESET}"
pacstrap /mnt base base-devel linux linux-firmware linux-headers nano networkmanager sudo git amd-ucode --noconfirm --needed
check_status "Base system installation"

genfstab -U /mnt >> /mnt/etc/fstab
check_status "Fstab generation"

# Post-Install Configuration
breaker
echo -e "${GREEN}Configuring Your System...${RESET}"
cat <<EOF > /mnt/root/post-install.sh
#!/usr/bin/env bash

# Enable essential services
systemctl enable NetworkManager systemd-timesyncd

# Install PipeWire for sound
pacman -S pipewire pipewire-alsa pipewire-pulse wireplumber --noconfirm --needed

# Remove PulseAudio (if installed) and set PipeWire as default
if pacman -Q pulseaudio &>/dev/null; then
    pacman -Rns pulseaudio --noconfirm
fi

# Set PipeWire as default
ln -sf /usr/bin/pipewire /usr/bin/pulseaudio
ln -sf /usr/bin/pipewire /usr/bin/pulseaudio-ctl
systemctl --user enable pipewire pipewire-pulse

# Bootloader setup
pacman -S grub efibootmgr os-prober --noconfirm --needed
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ArchLinux
grub-mkconfig -o /boot/grub/grub.cfg

# Power Management
pacman -S tlp --noconfirm --needed
systemctl enable tlp

# Install yay (AUR helper)
pacman -S base-devel git --noconfirm --needed
sudo -u "$USERNAME" bash <<YAY
cd /home/$USERNAME
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si --noconfirm
rm -rf yay-bin
YAY

echo "Installation complete! Reboot now."
EOF

chmod +x /mnt/root/post-install.sh
arch-chroot /mnt bash /root/post-install.sh
check_status "Final setup"

rm /mnt/root/post-install.sh

breaker
echo -e "${GREEN}Installation complete! Type 'reboot' to start your new Arch Linux.${RESET}"
breaker
