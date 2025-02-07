#!/usr/bin/env bash

# Prompt for partitions
echo "Please enter EFI partition: (example /dev/sda1 or /dev/nvme0n1p1)"
read EFI

echo "Please enter Root (/) partition: (example /dev/sda3)"
read ROOT  

# ZRAM or traditional swap?
echo "Do you want to enable ZRAM instead of a swap partition? (y/n)"
read ZRAM_ENABLE

if [[ "$ZRAM_ENABLE" == "n" ]]; then
    echo "Please enter Swap partition (leave empty to skip):"
    read SWAP  
fi

# Optimizing mirrorlist
echo "Updating mirrorlist for faster downloads..."
pacman -Sy reflector --noconfirm --needed
reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# Format filesystems
echo -e "\nCreating Filesystems...\n"
existing_fs=$(blkid -s TYPE -o value "$EFI")
if [[ "$existing_fs" != "vfat" ]]; then
    mkfs.vfat -F32 "$EFI"
fi
mkfs.ext4 "${ROOT}"

if [[ "$ZRAM_ENABLE" == "n" && -n "$SWAP" ]]; then
    mkswap "$SWAP"
fi

# Mount target
mount "${ROOT}" /mnt
mount --mkdir "$EFI" /mnt/boot/efi

if [[ "$ZRAM_ENABLE" == "n" && -n "$SWAP" ]]; then
    swapon "$SWAP"
fi

# Enable multi-threaded downloads in pacman
sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf

echo "--------------------------------------"
echo "-- INSTALLING Base Arch Linux --"
echo "--------------------------------------"
pacstrap /mnt base base-devel linux linux-firmware linux-headers nano networkmanager sudo git --noconfirm --needed

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

cat <<REALEND > /mnt/next.sh
#!/usr/bin/env bash

# Set up username and password
useradd -m sudin
usermod -c "Sudin" sudin
usermod -aG wheel,storage,power,audio,video sudin
echo "sudin:password" | chpasswd

# Enable sudo for user
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
sed -i 's/^%wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers

# Set up language and locale
echo "-------------------------------------------------"
echo "Setting up Language & Locale"
echo "-------------------------------------------------"
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set timezone
ln -sf /usr/share/zoneinfo/Asia/Kathmandu /etc/localtime
hwclock --systohc

# Set hostname
echo "archlinux" > /etc/hostname
cat <<EOF > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   archlinux.localdomain   archlinux
EOF

# Setup ZRAM if selected
if [[ "$ZRAM_ENABLE" == "y" ]]; then
    echo "zram" > /etc/modules-load.d/zram.conf
    echo "options zram num_devices=1" > /etc/modprobe.d/zram.conf
    echo "KERNEL==\"zram0\", ATTR{disksize}=\"8G\", TAG+=\"systemd\"" > /etc/udev/rules.d/99-zram.rules
    echo "/dev/zram0 none swap defaults 0 0" >> /etc/fstab
fi

echo "-------------------------------------------------"
echo "Installing Drivers & Packages"
echo "-------------------------------------------------"
# Install AMD CPU/mGPU, NVIDIA, and other necessary packages
pacman -S mesa-utils vulkan-radeon libva-mesa-driver libva-utils \
          nvidia nvidia-utils nvidia-settings nvidia-prime \
          pipewire pipewire-alsa pipewire-pulse wireplumber pipewire-jack \
          base-devel --noconfirm --needed

# Enable services
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable --now pipewire pipewire-pulse

echo "-------------------------------------------------"
echo "Installing yay (AUR Helper)"
echo "-------------------------------------------------"
git clone https://aur.archlinux.org/yay-bin.git /home/sudin/yay-bin
chown -R sudin:sudin /home/sudin/yay-bin
cd /home/sudin/yay-bin
sudo -u sudin makepkg -si --noconfirm
cd ~
rm -rf /home/sudin/yay-bin

echo "--------------------------------------"
echo "-- Bootloader Installation  --"
echo "--------------------------------------"
pacman -S grub efibootmgr --noconfirm --needed
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ArchLinux
grub-mkconfig -o /boot/grub/grub.cfg

echo "-------------------------------------------------"
echo "Install Complete, You can reboot now"
echo "-------------------------------------------------"

REALEND

arch-chroot /mnt bash /next.sh
