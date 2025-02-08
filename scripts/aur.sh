#!/bin/bash

# Change this to your username
USERNAME="sudin"

# Clone Yay from the AUR repository
cd /home/$USERNAME
sudo git clone https://aur.archlinux.org/yay.git

# Change ownership of the cloned repo to the user
sudo chown -R $USERNAME:users yay

# Go to the yay directory and build the package
cd yay
makepkg -sri --needed --noconfirm

# Go back to your dotfiles directory (make sure the path is correct)
cd /path/to/your/dotfiles
