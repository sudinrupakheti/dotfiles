source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

HISTFILE=~/.history
HISTSIZE=10000
SAVEHIST=50000

setopt inc_append_history

eval "$(starship init zsh)"
export PATH="/home/sudin/.local/bin:$PATH"
export PATH="$PATH:/home/sudin/AndroidSDK/cmdline-tools/latest/bin:/home/sudin/AndroidSDK/emulator"

alias update-initramfs="mkinitcpio -P"
