#!/bin/bash

USERNAME="sudin"

# Install Zsh
sudo pacman -S zsh --noconfirm --needed

# Set Zsh as the default shell
chsh -s /bin/zsh $USERNAME

# Copy the .zshrc (if you want it)
cp .zshrc /home/$USERNAME/.zshrc
