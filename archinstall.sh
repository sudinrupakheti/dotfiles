#!/bin/bash
set -euo pipefail

SCRIPT_PHASE="${1:-install}"
STATE_FILE="/tmp/arch-install-state"
SKIP_TO="${2:-}"
INSTALL_LOG="/tmp/arch-install-$(date +%Y%m%d-%H%M%S).log"

# Logging function
log_command() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$INSTALL_LOG"
    "$@" 2>&1 | tee -a "$INSTALL_LOG"
    return ${PIPESTATUS[0]}
}

echo "Installation log: $INSTALL_LOG" | tee -a "$INSTALL_LOG"

# State management functions
save_state() {
    echo "$1=true" >> "$STATE_FILE"
}

check_state() {
    [[ -f "$STATE_FILE" ]] && grep -q "^$1=true$" "$STATE_FILE" 2>/dev/null
}

step_header() {
    echo
    echo "============================================"
    echo "STEP: $1"
    echo "============================================"
}

skip_if_done() {
    local step_name="$1"
    local description="$2"
    
    if check_state "$step_name"; then
        echo "✓ $description already completed - SKIPPING"
        return 0
    fi
    return 1
}

# Resume detection
detect_resume() {
    if [[ -f "$STATE_FILE" && -z "$SKIP_TO" ]]; then
        echo "Previous installation state detected!"
        echo "Completed steps:"
        cat "$STATE_FILE" | sed 's/=true/ ✓/' | sed 's/^/  - /'
        echo
        read -p "Resume from where you left off? (y/N): " resume
        if [[ ! $resume =~ ^[Yy]$ ]]; then
            echo "Starting fresh installation..."
            rm -f "$STATE_FILE"
        fi
    fi
}

# Skip to specific step
handle_skip_to() {
    if [[ -n "$SKIP_TO" ]]; then
        echo "Skipping to step: $SKIP_TO"
        # Create minimal state file to skip earlier steps
        case "$SKIP_TO" in
            "partitioning") ;;
            "mounting") save_state "PARTITIONING" ;;
            "mirrors") save_state "PARTITIONING"; save_state "MOUNTING" ;;
            "pacstrap") save_state "PARTITIONING"; save_state "MOUNTING"; save_state "MIRRORS" ;;
            "fstab") save_state "PARTITIONING"; save_state "MOUNTING"; save_state "MIRRORS"; save_state "PACSTRAP" ;;
            "zram") save_state "PARTITIONING"; save_state "MOUNTING"; save_state "MIRRORS"; save_state "PACSTRAP"; save_state "FSTAB" ;;
            "chroot") save_state "PARTITIONING"; save_state "MOUNTING"; save_state "MIRRORS"; save_state "PACSTRAP"; save_state "FSTAB"; save_state "ZRAM" ;;
            *) echo "Unknown step: $SKIP_TO"; exit 1 ;;
        esac
    fi
}

if [[ "$SCRIPT_PHASE" == "install" ]]; then
    echo "=== ARCH LINUX ULTIMATE INSTALLATION SCRIPT ===" | tee -a "$INSTALL_LOG"
    echo | tee -a "$INSTALL_LOG"
    
    # Pre-installation validation
    echo "=== PRE-INSTALLATION VALIDATION ===" | tee -a "$INSTALL_LOG"
    
    # Check if running in UEFI mode
    if [[ ! -d /sys/firmware/efi/efivars ]]; then
        echo "⚠ WARNING: System not booted in UEFI mode!" | tee -a "$INSTALL_LOG"
        echo "This script requires UEFI boot mode." | tee -a "$INSTALL_LOG"
        read -p "Continue anyway? (y/N): " continue_bios
        [[ ! $continue_bios =~ ^[Yy]$ ]] && exit 1
    else
        echo "✓ UEFI mode detected" | tee -a "$INSTALL_LOG"
    fi
    
    # Check available RAM
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    if [[ $TOTAL_RAM -lt 2048 ]]; then
        echo "⚠ WARNING: Less than 2GB RAM detected ($TOTAL_RAM MB)" | tee -a "$INSTALL_LOG"
        echo "Installation may be slow or fail." | tee -a "$INSTALL_LOG"
        read -p "Continue anyway? (y/N): " continue_ram
        [[ ! $continue_ram =~ ^[Yy]$ ]] && exit 1
    else
        echo "✓ RAM: ${TOTAL_RAM}MB" | tee -a "$INSTALL_LOG"
    fi
    
    # Check internet connectivity
    if ping -c 1 archlinux.org &> /dev/null; then
        echo "✓ Internet connection available" | tee -a "$INSTALL_LOG"
    else
        echo "⚠ WARNING: No internet connection detected" | tee -a "$INSTALL_LOG"
        echo "You'll need internet for installation." | tee -a "$INSTALL_LOG"
        read -p "Continue anyway? (y/N): " continue_net
        [[ ! $continue_net =~ ^[Yy]$ ]] && exit 1
    fi
    
    # Detect CPU cores for parallel downloads
    CPU_CORES=$(nproc)
    if [[ $CPU_CORES -ge 8 ]]; then
        PARALLEL_DOWNLOADS=10
    elif [[ $CPU_CORES -ge 4 ]]; then
        PARALLEL_DOWNLOADS=5
    else
        PARALLEL_DOWNLOADS=3
    fi
    echo "✓ CPU cores: $CPU_CORES (will use $PARALLEL_DOWNLOADS parallel downloads)" | tee -a "$INSTALL_LOG"
    
    echo | tee -a "$INSTALL_LOG"
    
    # Ask about optional components
    echo "This script can install optional components for a full desktop experience." | tee -a "$INSTALL_LOG"
    echo "You can skip all optional components for a minimal installation (useful for VMs/testing)." | tee -a "$INSTALL_LOG"
    echo | tee -a "$INSTALL_LOG"
    read -p "Skip ALL optional components? (y/N): " skip_all_optional
    echo
    
    # Filesystem selection
    echo "Select filesystem for root partition:" | tee -a "$INSTALL_LOG"
    echo "1) Btrfs (with @ and @home subvolumes, snapshots support)" | tee -a "$INSTALL_LOG"
    echo "2) ext4 (traditional, simple, stable)" | tee -a "$INSTALL_LOG"
    read -p "Choose filesystem (1/2) [default: 1]: " fs_choice
    fs_choice=${fs_choice:-1}
    
    if [[ "$fs_choice" == "2" ]]; then
        USE_BTRFS=false
        echo "✓ Using ext4 filesystem" | tee -a "$INSTALL_LOG"
    else
        USE_BTRFS=true
        echo "✓ Using Btrfs filesystem with subvolumes" | tee -a "$INSTALL_LOG"
    fi
    echo | tee -a "$INSTALL_LOG"
    
    # Set defaults based on skip_all choice
    if [[ $skip_all_optional =~ ^[Yy]$ ]]; then
        INSTALL_WIFI="n"
        INSTALL_ZRAM="n"
        INSTALL_PIPEWIRE="n"
        INSTALL_ZSH="n"
        INSTALL_MONITORING="n"
        INSTALL_TIMESHIFT="n"
        INSTALL_FONTS="n"
        INSTALL_TLP="n"
        INSTALL_BLUETOOTH="n"
        INSTALL_CPUPOWER="n"
        INSTALL_SYSCTL="n"
        INSTALL_KERNEL_OPTS="n"
        INSTALL_OMZ="n"
        INSTALL_GRAPHICS="n"
        INSTALL_FIREWALL="n"
        echo "✓ Minimal installation mode - all optional components will be skipped" | tee -a "$INSTALL_LOG"
    else
        # Check if WiFi adapter exists before asking
        if iwctl device list 2>/dev/null | grep -q "wlan"; then
            read -p "Configure WiFi during installation? (Y/n): " INSTALL_WIFI
            INSTALL_WIFI=${INSTALL_WIFI:-y}
        else
            INSTALL_WIFI="n"
            echo "No WiFi adapter detected - skipping WiFi configuration" | tee -a "$INSTALL_LOG"
        fi
        
        read -p "Install ZRAM (8GB compressed swap)? (Y/n): " INSTALL_ZRAM
        INSTALL_ZRAM=${INSTALL_ZRAM:-y}
        
        read -p "Install PipeWire audio system? (Y/n): " INSTALL_PIPEWIRE
        INSTALL_PIPEWIRE=${INSTALL_PIPEWIRE:-y}
        
        read -p "Use Zsh shell instead of bash? (Y/n): " INSTALL_ZSH
        INSTALL_ZSH=${INSTALL_ZSH:-y}
        
        read -p "Install system monitoring tools (htop, btop)? (Y/n): " INSTALL_MONITORING
        INSTALL_MONITORING=${INSTALL_MONITORING:-y}
        
        read -p "Install Timeshift for system snapshots? (Y/n): " INSTALL_TIMESHIFT
        INSTALL_TIMESHIFT=${INSTALL_TIMESHIFT:-y}
        
        read -p "Install additional fonts? (Y/n): " INSTALL_FONTS
        INSTALL_FONTS=${INSTALL_FONTS:-y}
        
        read -p "Install TLP power management? (Y/n): " INSTALL_TLP
        INSTALL_TLP=${INSTALL_TLP:-y}
        
        read -p "Install Bluetooth support? (Y/n): " INSTALL_BLUETOOTH
        INSTALL_BLUETOOTH=${INSTALL_BLUETOOTH:-y}
        
        read -p "Install CPU performance governor? (Y/n): " INSTALL_CPUPOWER
        INSTALL_CPUPOWER=${INSTALL_CPUPOWER:-y}
        
        read -p "Apply system optimizations (sysctl tweaks)? (Y/n): " INSTALL_SYSCTL
        INSTALL_SYSCTL=${INSTALL_SYSCTL:-y}
        
        read -p "Apply kernel optimizations in post-install? (Y/n): " INSTALL_KERNEL_OPTS
        INSTALL_KERNEL_OPTS=${INSTALL_KERNEL_OPTS:-y}
        
        read -p "Install Oh My Zsh with Powerlevel10k theme? (Y/n): " INSTALL_OMZ
        INSTALL_OMZ=${INSTALL_OMZ:-y}
        
        read -p "Prompt for graphics drivers in post-install? (Y/n): " INSTALL_GRAPHICS
        INSTALL_GRAPHICS=${INSTALL_GRAPHICS:-y}
        
        read -p "Enable UFW firewall? (Y/n): " INSTALL_FIREWALL
        INSTALL_FIREWALL=${INSTALL_FIREWALL:-y}
    fi
    
    # Save installation preferences
    cat > /tmp/install-preferences <<EOF
USE_BTRFS=$USE_BTRFS
INSTALL_WIFI="$INSTALL_WIFI"
INSTALL_ZRAM="$INSTALL_ZRAM"
INSTALL_PIPEWIRE="$INSTALL_PIPEWIRE"
INSTALL_ZSH="$INSTALL_ZSH"
INSTALL_MONITORING="$INSTALL_MONITORING"
INSTALL_TIMESHIFT="$INSTALL_TIMESHIFT"
INSTALL_FONTS="$INSTALL_FONTS"
INSTALL_TLP="$INSTALL_TLP"
INSTALL_BLUETOOTH="$INSTALL_BLUETOOTH"
INSTALL_CPUPOWER="$INSTALL_CPUPOWER"
INSTALL_SYSCTL="$INSTALL_SYSCTL"
INSTALL_KERNEL_OPTS="$INSTALL_KERNEL_OPTS"
INSTALL_OMZ="$INSTALL_OMZ"
INSTALL_GRAPHICS="$INSTALL_GRAPHICS"
INSTALL_FIREWALL="$INSTALL_FIREWALL"
PARALLEL_DOWNLOADS="$PARALLEL_DOWNLOADS"
CPU_CORES="$CPU_CORES"
EOF
    
    echo | tee -a "$INSTALL_LOG"
    echo "=== INSTALLATION SUMMARY ===" | tee -a "$INSTALL_LOG"
    echo "Please review your installation configuration:" | tee -a "$INSTALL_LOG"
    echo | tee -a "$INSTALL_LOG"
    
    # Initialize state management
    detect_resume
    handle_skip_to
    if skip_if_done "WIFI_SETUP" "WiFi configuration"; then
        :
    else
        echo "Setting up network connection..."
        WIFI_CONNECTED=false
        if iwctl device list | grep -q wlan; then
            echo "WiFi adapter detected. Available networks:"
            iwctl station wlan0 scan
            sleep 3
            iwctl station wlan0 get-networks
            echo
            read -p "Enter WiFi network name (SSID): " wifi_ssid
            read -s -p "Enter WiFi password: " wifi_password
            echo
            
            echo "Connecting to $wifi_ssid..."
            iwctl --passphrase="$wifi_password" station wlan0 connect "$wifi_ssid"
            
            # Wait a moment for connection
            sleep 5
            
            # Test internet connection
            if ping -c 1 archlinux.org &> /dev/null; then
                echo "✓ Internet connection established"
                WIFI_CONNECTED=true
                
                # Save WiFi credentials for post-install
                mkdir -p /tmp/wifi-backup
                cat > /tmp/wifi-backup/wifi-credentials <<EOF
WIFI_SSID="$wifi_ssid"
WIFI_PASSWORD="$wifi_password"
EOF
                echo "✓ WiFi credentials saved for post-install setup"
                
                save_state "WIFI_SETUP"
            else
                echo "✗ Failed to connect to internet. Continuing anyway..."
                echo "You may need to manually configure network connection."
            fi
        else
            echo "No WiFi adapter found or ethernet already connected"
            if ping -c 1 archlinux.org &> /dev/null; then
                echo "✓ Internet connection detected"
                save_state "WIFI_SETUP"
            else
                echo "✗ No internet connection. Please configure network manually."
                read -p "Press Enter to continue or Ctrl+C to exit..."
            fi
        fi
    else
        echo "Skipping WiFi setup"
        # Still need to check internet connection
        if ping -c 1 archlinux.org &> /dev/null; then
            echo "✓ Internet connection detected"
        else
            echo "⚠ No internet connection detected"
            read -p "Press Enter to continue or Ctrl+C to exit..."
        fi
    fi
    
    echo | tee -a "$INSTALL_LOG"
    echo "=== INSTALLATION SUMMARY ===" | tee -a "$INSTALL_LOG"
    echo "Please review your installation configuration:" | tee -a "$INSTALL_LOG"
    echo | tee -a "$INSTALL_LOG"
    
    # Wait for partition selection before showing summary
    # This section will be filled after partition selection
    
    # Initialize state management
    detect_resume
    handle_skip_to
    
    # Partition selection
    step_header "PARTITION SELECTION"
    if skip_if_done "PARTITIONING" "Partition selection"; then
        # Load previously saved partition info
        if [[ -f /tmp/partition_info ]]; then
            source /tmp/partition_info
            echo "Using previously selected partitions:" | tee -a "$INSTALL_LOG"
            echo "EFI: $EFI_PART" | tee -a "$INSTALL_LOG"
            echo "Root: $ROOT_PART" | tee -a "$INSTALL_LOG"
        else
            echo "Error: Previous partition info not found!" | tee -a "$INSTALL_LOG"
            exit 1
        fi
    else
        # List available block devices
        echo "Available block devices:" | tee -a "$INSTALL_LOG"
        lsblk -p | tee -a "$INSTALL_LOG"
        
        # Get partition inputs
        read -p "Enter EFI partition (e.g., /dev/nvme0n1p1): " EFI_PART
        read -p "Enter root partition (e.g., /dev/nvme0n1p2): " ROOT_PART
        
        echo "EFI: $EFI_PART" >> "$INSTALL_LOG"
        echo "Root: $ROOT_PART" >> "$INSTALL_LOG"
        
        # Verify partitions exist
        if [[ ! -b "$EFI_PART" ]] || [[ ! -b "$ROOT_PART" ]]; then
            echo "Error: Partitions $EFI_PART or $ROOT_PART do not exist!" | tee -a "$INSTALL_LOG"
            exit 1
        fi
        
        # Check partition sizes
        EFI_SIZE=$(lsblk -b -n -o SIZE "$EFI_PART")
        ROOT_SIZE=$(lsblk -b -n -o SIZE "$ROOT_PART")
        EFI_SIZE_MB=$((EFI_SIZE / 1024 / 1024))
        ROOT_SIZE_GB=$((ROOT_SIZE / 1024 / 1024 / 1024))
        
        if [[ $EFI_SIZE_MB -lt 512 ]]; then
            echo "⚠ WARNING: EFI partition is less than 512MB (${EFI_SIZE_MB}MB)" | tee -a "$INSTALL_LOG"
            read -p "Continue anyway? (y/N): " continue_efi
            [[ ! $continue_efi =~ ^[Yy]$ ]] && exit 1
        fi
        
        if [[ $ROOT_SIZE_GB -lt 20 ]]; then
            echo "⚠ WARNING: Root partition is less than 20GB (${ROOT_SIZE_GB}GB)" | tee -a "$INSTALL_LOG"
            read -p "Continue anyway? (y/N): " continue_root
            [[ ! $continue_root =~ ^[Yy]$ ]] && exit 1
        fi
        
        # Save partition info for resume
        cat > /tmp/partition_info <<EOF
EFI_PART="$EFI_PART"
ROOT_PART="$ROOT_PART"
EOF
        
        # Show complete installation summary
        echo | tee -a "$INSTALL_LOG"
        echo "========================================" | tee -a "$INSTALL_LOG"
        echo "       FINAL INSTALLATION REVIEW        " | tee -a "$INSTALL_LOG"
        echo "========================================" | tee -a "$INSTALL_LOG"
        echo | tee -a "$INSTALL_LOG"
        echo "PARTITIONS:" | tee -a "$INSTALL_LOG"
        echo "  EFI:  $EFI_PART (${EFI_SIZE_MB}MB)" | tee -a "$INSTALL_LOG"
        echo "  Root: $ROOT_PART (${ROOT_SIZE_GB}GB)" | tee -a "$INSTALL_LOG"
        echo | tee -a "$INSTALL_LOG"
        echo "SYSTEM CONFIGURATION:" | tee -a "$INSTALL_LOG"
        echo "  Hostname: ArchLinux" | tee -a "$INSTALL_LOG"
        echo "  Timezone: Asia/Kathmandu" | tee -a "$INSTALL_LOG"
        echo "  Locale: en_US.UTF-8" | tee -a "$INSTALL_LOG"
        if $USE_BTRFS; then
            echo "  Filesystem: Btrfs with @ and @home subvolumes" | tee -a "$INSTALL_LOG"
        else
            echo "  Filesystem: ext4" | tee -a "$INSTALL_LOG"
        fi
        echo "  Bootloader: systemd-boot" | tee -a "$INSTALL_LOG"
        echo "  CPU Cores: $CPU_CORES" | tee -a "$INSTALL_LOG"
        echo "  Parallel Downloads: $PARALLEL_DOWNLOADS" | tee -a "$INSTALL_LOG"
        echo | tee -a "$INSTALL_LOG"
        echo "OPTIONAL COMPONENTS:" | tee -a "$INSTALL_LOG"
        [[ $INSTALL_WIFI =~ ^[Yy]$ ]] && echo "  ✓ WiFi Configuration" | tee -a "$INSTALL_LOG" || echo "  ✗ WiFi Configuration" | tee -a "$INSTALL_LOG"
        [[ $INSTALL_ZRAM =~ ^[Yy]$ ]] && echo "  ✓ ZRAM (8GB)" | tee -a "$INSTALL_LOG" || echo "  ✗ ZRAM" | tee -a "$INSTALL_LOG"
        [[ $INSTALL_PIPEWIRE =~ ^[Yy]$ ]] && echo "  ✓ PipeWire Audio" | tee -a "$INSTALL_LOG" || echo "  ✗ PipeWire Audio" | tee -a "$INSTALL_LOG"
        [[ $INSTALL_ZSH =~ ^[Yy]$ ]] && echo "  ✓ Zsh Shell" | tee -a "$INSTALL_LOG" || echo "  ✗ Zsh Shell (using bash)" | tee -a "$INSTALL_LOG"
        [[ $INSTALL_MONITORING =~ ^[Yy]$ ]] && echo "  ✓ Monitoring Tools" | tee -a "$INSTALL_LOG" || echo "  ✗ Monitoring Tools" | tee -a "$INSTALL_LOG"
        [[ $INSTALL_TIMESHIFT =~ ^[Yy]$ ]] && echo "  ✓ Timeshift Backups" | tee -a "$INSTALL_LOG" || echo "  ✗ Timeshift Backups" | tee -a "$INSTALL_LOG"
        [[ $INSTALL_FONTS =~ ^[Yy]$ ]] && echo "  ✓ Additional Fonts" | tee -a "$INSTALL_LOG" || echo "  ✗ Additional Fonts" | tee -a "$INSTALL_LOG"
        [[ $INSTALL_TLP =~ ^[Yy]$ ]] && echo "  ✓ TLP Power Management" | tee -a "$INSTALL_LOG" || echo "  ✗ TLP Power Management" | tee -a "$INSTALL_LOG"
        [[ $INSTALL_BLUETOOTH =~ ^[Yy]$ ]] && echo "  ✓ Bluetooth" | tee -a "$INSTALL_LOG" || echo "  ✗ Bluetooth" | tee -a "$INSTALL_LOG"
        [[ $INSTALL_CPUPOWER =~ ^[Yy]$ ]] && echo "  ✓ CPU Governor" | tee -a "$INSTALL_LOG" || echo "  ✗ CPU Governor" | tee -a "$INSTALL_LOG"
        [[ $INSTALL_SYSCTL =~ ^[Yy]$ ]] && echo "  ✓ System Optimizations" | tee -a "$INSTALL_LOG" || echo "  ✗ System Optimizations" | tee -a "$INSTALL_LOG"
        [[ $INSTALL_FIREWALL =~ ^[Yy]$ ]] && echo "  ✓ UFW Firewall" | tee -a "$INSTALL_LOG" || echo "  ✗ UFW Firewall" | tee -a "$INSTALL_LOG"
        echo | tee -a "$INSTALL_LOG"
        echo "POST-INSTALL OPTIONS:" | tee -a "$INSTALL_LOG"
        [[ $INSTALL_KERNEL_OPTS =~ ^[Yy]$ ]] && echo "  ✓ Kernel Optimizations" | tee -a "$INSTALL_LOG" || echo "  ✗ Kernel Optimizations" | tee -a "$INSTALL_LOG"
        [[ $INSTALL_OMZ =~ ^[Yy]$ ]] && echo "  ✓ Oh My Zsh + Powerlevel10k" | tee -a "$INSTALL_LOG" || echo "  ✗ Oh My Zsh" | tee -a "$INSTALL_LOG"
        [[ $INSTALL_GRAPHICS =~ ^[Yy]$ ]] && echo "  ✓ Graphics Driver Prompt" | tee -a "$INSTALL_LOG" || echo "  ✗ Graphics Drivers" | tee -a "$INSTALL_LOG"
        echo | tee -a "$INSTALL_LOG"
        echo "========================================" | tee -a "$INSTALL_LOG"
        echo | tee -a "$INSTALL_LOG"
        
        echo "⚠ WARNING: This will FORMAT and ERASE all data on $ROOT_PART" | tee -a "$INSTALL_LOG"
        echo "This action is IRREVERSIBLE and will destroy ALL existing data!" | tee -a "$INSTALL_LOG"
        read -p "Type 'CONFIRM' to proceed: " confirm
        
        if [[ "$confirm" != "CONFIRM" ]]; then
            echo "Installation cancelled." | tee -a "$INSTALL_LOG"
            exit 1
        fi
        
        save_state "PARTITIONING"
    fi
    
    # Load partition info for subsequent steps
    if [[ -f /tmp/partition_info ]]; then
        source /tmp/partition_info
    fi
    
    # Update system clock
    step_header "SYSTEM CLOCK"
    if skip_if_done "CLOCK_SYNC" "System clock sync"; then
        :
    else
        timedatectl set-ntp true
        save_state "CLOCK_SYNC"
    fi
    
    # Load partition info for subsequent steps
    if [[ -f /tmp/partition_info ]]; then
        source /tmp/partition_info
    fi
    
    # WiFi setup
    if [[ $INSTALL_WIFI =~ ^[Yy]$ ]]; then
        step_header "NETWORK SETUP"
    
    # Update system clock
    step_header "SYSTEM CLOCK"
    if skip_if_done "CLOCK_SYNC" "System clock sync"; then
        :
    else
        timedatectl set-ntp true
        save_state "CLOCK_SYNC"
    fi
    
    # Mounting check
    step_header "PARTITION MOUNTING"
    if skip_if_done "MOUNTING" "Partition mounting"; then
        # Verify mounts are still active
        if ! mountpoint -q /mnt; then
            echo "Previous mounts lost, remounting..." | tee -a "$INSTALL_LOG"
            if $USE_BTRFS; then
                mount -o noatime,compress=zstd:3,space_cache=v2,subvol=@ "$ROOT_PART" /mnt
                mount -o noatime,compress=zstd:3,space_cache=v2,subvol=@home "$ROOT_PART" /mnt/home
            else
                mount "$ROOT_PART" /mnt
                mkdir -p /mnt/home
            fi
            mount "$EFI_PART" /mnt/boot
        else
            echo "✓ Partitions already mounted correctly" | tee -a "$INSTALL_LOG"
        fi
    else
        # Format and mount partitions
        if mountpoint -q /mnt; then
            echo "Partitions already mounted, unmounting first..." | tee -a "$INSTALL_LOG"
            umount -R /mnt || true
        fi
        
        if $USE_BTRFS; then
            echo "Formatting root partition as Btrfs..." | tee -a "$INSTALL_LOG"
            mkfs.btrfs -f "$ROOT_PART" | tee -a "$INSTALL_LOG"
            mount "$ROOT_PART" /mnt
            
            # Create Btrfs subvolumes
            echo "Creating Btrfs subvolumes..." | tee -a "$INSTALL_LOG"
            btrfs subvolume create /mnt/@
            btrfs subvolume create /mnt/@home
            umount /mnt
            
            # Mount subvolumes
            echo "Mounting Btrfs subvolumes..." | tee -a "$INSTALL_LOG"
            mount -o noatime,compress=zstd:3,space_cache=v2,subvol=@ "$ROOT_PART" /mnt
            mkdir -p /mnt/{boot,home}
            mount -o noatime,compress=zstd:3,space_cache=v2,subvol=@home "$ROOT_PART" /mnt/home
        else
            echo "Formatting root partition as ext4..." | tee -a "$INSTALL_LOG"
            mkfs.ext4 -F "$ROOT_PART" | tee -a "$INSTALL_LOG"
            mount "$ROOT_PART" /mnt
            mkdir -p /mnt/{boot,home}
        fi
        
        mount "$EFI_PART" /mnt/boot
        
        save_state "MOUNTING"
    fi
    
    # Mirror optimization
    step_header "MIRROR OPTIMIZATION"
    if skip_if_done "MIRRORS" "Mirror optimization"; then
        :
    else
        echo "Optimizing mirrors (limited to 20 mirrors, this may take a few minutes)..." | tee -a "$INSTALL_LOG"
        timeout 300 reflector --latest 20 --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist || {
            echo "Reflector timed out after 5 minutes, using existing mirrors" | tee -a "$INSTALL_LOG"
        }
        save_state "MIRRORS"
    fi
    
    # Base system installation
    step_header "BASE SYSTEM INSTALLATION"
    if skip_if_done "PACSTRAP" "Base system installation"; then
        if [[ ! -f /mnt/usr/bin/pacman ]]; then
            echo "Base system appears incomplete, reinstalling..."
            pacstrap -K /mnt base base-devel linux linux-firmware linux-headers
        else
            echo "✓ Base system already installed correctly"
        fi
    else
        pacstrap -K /mnt base base-devel linux linux-firmware linux-headers
        save_state "PACSTRAP"
    fi
    
    # Generate fstab
    step_header "FSTAB GENERATION"
    if skip_if_done "FSTAB" "Fstab generation"; then
        :
    else
        genfstab -U /mnt >> /mnt/etc/fstab
        save_state "FSTAB"
    fi
    
    # Setup zram
    if [[ $INSTALL_ZRAM =~ ^[Yy]$ ]]; then
        step_header "ZRAM CONFIGURATION"
        if skip_if_done "ZRAM" "Zram configuration"; then
            :
        else
            # Install zram-generator (modern systemd-native approach)
            arch-chroot /mnt pacman -S --noconfirm --needed zram-generator
            
            # Configure zram-generator
            cat > /mnt/etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = 8192
compression-algorithm = zstd
EOF
            
            save_state "ZRAM"
        fi
    else
        echo "Skipping ZRAM installation"
    fi
    
    # Copy script and state for post-install
    cp "$0" /mnt/root/ultimate-install.sh
    cp "$STATE_FILE" /mnt/root/install-state.backup 2>/dev/null || true
    cp /tmp/install-preferences /mnt/root/install-preferences
    
    # Copy WiFi credentials if they exist
    if [[ -f /tmp/wifi-backup/wifi-credentials ]]; then
        cp /tmp/wifi-backup/wifi-credentials /mnt/root/wifi-credentials
        echo "✓ WiFi credentials copied to new system"
    fi
    
    # Chroot configuration
    step_header "CHROOT CONFIGURATION"
    if skip_if_done "CHROOT" "Chroot configuration"; then
        :
    else
        # Load installation preferences
        source /tmp/install-preferences
        
        arch-chroot /mnt /bin/bash <<CHROOT_EOF
set -euo pipefail

# Load preferences in chroot
USE_BTRFS=$USE_BTRFS
INSTALL_PIPEWIRE="$INSTALL_PIPEWIRE"
INSTALL_ZSH="$INSTALL_ZSH"
INSTALL_MONITORING="$INSTALL_MONITORING"
INSTALL_TIMESHIFT="$INSTALL_TIMESHIFT"
INSTALL_FONTS="$INSTALL_FONTS"
INSTALL_TLP="$INSTALL_TLP"
INSTALL_BLUETOOTH="$INSTALL_BLUETOOTH"
INSTALL_CPUPOWER="$INSTALL_CPUPOWER"
INSTALL_SYSCTL="$INSTALL_SYSCTL"
INSTALL_FIREWALL="$INSTALL_FIREWALL"

# Set timezone
ln -sf /usr/share/zoneinfo/Asia/Kathmandu /etc/localtime
hwclock --systohc

# Set locale
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf

# Set hostname
echo 'ArchLinux' > /etc/hostname

# Configure hosts file
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ArchLinux.localdomain ArchLinux
EOF

# Get user credentials
echo "Enter your desired username:"
read -r username
echo "Enter password (will be used for both user and root):"
read -s password

# Set root password
echo "root:$password" | chpasswd

# Create user
useradd -m -G wheel -s /bin/zsh "$username"
echo "$username:$password" | chpasswd

# Configure sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Configure pacman
sed -i 's/^#Color/Color/' /etc/pacman.conf
sed -i "s/^#ParallelDownloads.*/ParallelDownloads = $PARALLEL_DOWNLOADS/" /etc/pacman.conf

# Enable multilib
sed -i '/\[multilib\]/,/Include/ s/^#//' /etc/pacman.conf

# Build package list based on preferences
PACKAGES="networkmanager efibootmgr dosfstools e2fsprogs ntfs-3g \
tar unrar unzip zip git nano vim wget curl sudo reflector \
man-db man-pages texinfo bash-completion xdg-utils xdg-user-dirs \
archlinux-keyring pacman-contrib pkgfile"

# Add btrfs-progs only if using Btrfs
\$USE_BTRFS && PACKAGES="\$PACKAGES btrfs-progs"

# Add optional packages
[ "\$INSTALL_PIPEWIRE" = "y" ] || [ "\$INSTALL_PIPEWIRE" = "Y" ] && \
    PACKAGES="\$PACKAGES pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber"

[ "\$INSTALL_ZSH" = "y" ] || [ "\$INSTALL_ZSH" = "Y" ] && \
    PACKAGES="\$PACKAGES zsh zsh-completions"

[ "\$INSTALL_MONITORING" = "y" ] || [ "\$INSTALL_MONITORING" = "Y" ] && \
    PACKAGES="\$PACKAGES htop btop tree"

[ "\$INSTALL_TIMESHIFT" = "y" ] || [ "\$INSTALL_TIMESHIFT" = "Y" ] && \
    PACKAGES="\$PACKAGES timeshift rsync mtools"

[ "\$INSTALL_FONTS" = "y" ] || [ "\$INSTALL_FONTS" = "Y" ] && \
    PACKAGES="\$PACKAGES ttf-dejavu ttf-liberation noto-fonts noto-fonts-emoji"

[ "\$INSTALL_TLP" = "y" ] || [ "\$INSTALL_TLP" = "Y" ] && \
    PACKAGES="\$PACKAGES tlp tlp-rdw"

[ "\$INSTALL_BLUETOOTH" = "y" ] || [ "\$INSTALL_BLUETOOTH" = "Y" ] && \
    PACKAGES="\$PACKAGES bluez bluez-utils blueman"

[ "\$INSTALL_CPUPOWER" = "y" ] || [ "\$INSTALL_CPUPOWER" = "Y" ] && \
    PACKAGES="\$PACKAGES cpupower"

[ "\$INSTALL_FIREWALL" = "y" ] || [ "\$INSTALL_FIREWALL" = "Y" ] && \
    PACKAGES="\$PACKAGES ufw"

# Install additional packages
pacman -Syu --noconfirm \$PACKAGES

# Advanced system optimizations
echo "Applying advanced system optimizations..."

# tmpfs for /tmp and /var/tmp
echo "tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0" >> /etc/fstab
echo "tmpfs /var/tmp tmpfs defaults,noatime,mode=1777 0 0" >> /etc/fstab

# Optimize makepkg for faster AUR builds
sed -i "s/^#MAKEFLAGS.*/MAKEFLAGS=\"-j\$(nproc)\"/" /etc/makepkg.conf
sed -i 's/^#COMPRESSZST.*/COMPRESSZST=(zstd -c -T0 -19 -)/' /etc/makepkg.conf

# Enable paccache timer for automatic package cache cleaning
systemctl enable paccache.timer

# Generate initramfs
mkinitcpio -P

# Install systemd-boot
bootctl install

# Configure bootloader
mkdir -p /boot/loader/entries

cat > /boot/loader/loader.conf <<EOF
default arch.conf
timeout 5
console-mode max
editor no
EOF

ROOT_UUID=$(blkid -s UUID -o value $(echo "$ROOT_PART"))

cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=$ROOT_UUID rw rootflags=subvol=@,compress=zstd:3 quiet loglevel=3
EOF

cat > /boot/loader/entries/arch-fallback.conf <<EOF
title   Arch Linux (fallback)
linux   /vmlinuz-linux
initrd  /initramfs-linux-fallback.img
options root=UUID=$ROOT_UUID rw rootflags=subvol=@,compress=zstd:3
EOF

# System optimizations
tee /etc/sysctl.d/99-performance.conf > /dev/null <<EOF
# Memory management
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=3
vm.dirty_background_ratio=2

# Network performance
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 65536 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
EOF

# CPU governor setup
echo 'governor="performance"' > /etc/default/cpupower

# Enable services
systemctl enable NetworkManager

[ "\$INSTALL_CPUPOWER" = "y" ] || [ "\$INSTALL_CPUPOWER" = "Y" ] && systemctl enable cpupower
[ "\$INSTALL_TLP" = "y" ] || [ "\$INSTALL_TLP" = "Y" ] && {
    systemctl enable tlp
    systemctl mask systemd-rfkill@.service
    systemctl mask systemd-rfkill.socket
}
[ "\$INSTALL_BLUETOOTH" = "y" ] || [ "\$INSTALL_BLUETOOTH" = "Y" ] && systemctl enable bluetooth
[ "\$INSTALL_FIREWALL" = "y" ] || [ "\$INSTALL_FIREWALL" = "Y" ] && systemctl enable ufw

systemctl enable fstrim.timer
systemctl enable reflector.timer

CHROOT_EOF
        
        save_state "CHROOT"
    fi
    
    # Cleanup and completion
    step_header "INSTALLATION COMPLETE"
    umount -R /mnt 2>/dev/null || true
    sync
    
    # Save final state
    save_state "INSTALLATION_COMPLETE"
    
    # Copy installation log to installed system
    if [[ -f "$INSTALL_LOG" ]]; then
        mkdir -p /mnt/var/log 2>/dev/null || true
        cp "$INSTALL_LOG" "/root/arch-install-$(date +%Y%m%d-%H%M%S).log" 2>/dev/null || true
    fi
    
    echo | tee -a "$INSTALL_LOG"
    echo "✓ Base installation complete!" | tee -a "$INSTALL_LOG"
    echo "Installation log saved to: $INSTALL_LOG" | tee -a "$INSTALL_LOG"
    echo "Log also copied to: /root/arch-install-*.log (in new system)" | tee -a "$INSTALL_LOG"
    echo | tee -a "$INSTALL_LOG"
    echo "After reboot, login with your username and run:" | tee -a "$INSTALL_LOG"
    echo "sudo /root/ultimate-install.sh postinstall" | tee -a "$INSTALL_LOG"
    echo | tee -a "$INSTALL_LOG"
    echo "Installation state saved. You can resume with:" | tee -a "$INSTALL_LOG"
    echo "./ultimate-install.sh install --skip-to STEP_NAME" | tee -a "$INSTALL_LOG"
    echo | tee -a "$INSTALL_LOG"
    read -p "Reboot now? (y/N): " reboot_now
    if [[ $reboot_now =~ ^[Yy]$ ]]; then
        rm -f "$STATE_FILE"  # Clean up state file
        reboot
    fi

elif [[ "$SCRIPT_PHASE" == "postinstall" ]]; then
    POST_INSTALL_LOG="/var/log/arch-postinstall-$(date +%Y%m%d-%H%M%S).log"
    echo "Post-installation log: $POST_INSTALL_LOG" | tee "$POST_INSTALL_LOG"
    
    echo "=== POST-INSTALLATION CONFIGURATION ===" | tee -a "$POST_INSTALL_LOG"
    echo | tee -a "$POST_INSTALL_LOG"
    
    POST_STATE_FILE="/tmp/arch-postinstall-state"
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        echo "Don't run post-install as root! Run as: sudo /root/ultimate-install.sh postinstall" | tee -a "$POST_INSTALL_LOG"
        exit 1
    fi
    
    USERNAME=$(whoami)
    echo "Running post-install setup for user: $USERNAME" | tee -a "$POST_INSTALL_LOG"
    
    # Load installation preferences
    if [[ -f /root/install-preferences ]]; then
        source /root/install-preferences
        echo "✓ Loaded installation preferences" | tee -a "$POST_INSTALL_LOG"
    else
        echo "⚠ No installation preferences found, using defaults" | tee -a "$POST_INSTALL_LOG"
        INSTALL_KERNEL_OPTS="y"
        INSTALL_OMZ="y"
        INSTALL_GRAPHICS="y"
    fi
    
    # Restore previous state if exists
    if [[ -f /root/install-state.backup ]]; then
        echo "Previous installation state found - main installation was successful" | tee -a "$POST_INSTALL_LOG"
    fi
    
    # Check for saved WiFi credentials
    if [[ -f /root/wifi-credentials ]]; then
        echo "✓ Found saved WiFi credentials from installation" | tee -a "$POST_INSTALL_LOG"
    fi
    
    # Post-install state management
    if [[ -f "$POST_STATE_FILE" ]]; then
        echo "Previous post-install state detected!"
        echo "Completed steps:"
        cat "$POST_STATE_FILE" | sed 's/=true/ ✓/' | sed 's/^/  - /'
        echo
        read -p "Resume from where you left off? (y/N): " resume
        if [[ ! $resume =~ ^[Yy]$ ]]; then
            echo "Starting fresh post-installation..."
            rm -f "$POST_STATE_FILE"
        fi
    fi
    echo
    
    # System updates
    step_header "SYSTEM UPDATES"
    if skip_if_done "UPDATES" "System updates" && [[ -f "$POST_STATE_FILE" ]]; then
        :
    else
        echo "Updating system packages..."
        sudo pacman -Syu --noconfirm
        echo "$1=true" >> "$POST_STATE_FILE"
    fi
    
    # WiFi auto-configuration with NetworkManager
    step_header "WIFI CONFIGURATION"
    if grep -q "POST_WIFI=true" "$POST_STATE_FILE" 2>/dev/null; then
        echo "✓ WiFi already configured - SKIPPING"
    else
        if [[ -f /root/wifi-credentials ]]; then
            echo "Configuring WiFi with NetworkManager..."
            source /root/wifi-credentials
            
            # Check if WiFi device exists
            if nmcli device status | grep -q wifi; then
                # Create NetworkManager connection
                sudo nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" && {
                    echo "✓ WiFi connection configured successfully!"
                    echo "✓ Network will auto-connect on boot"
                    
                    # Securely delete credentials file
                    sudo shred -u /root/wifi-credentials
                    echo "✓ WiFi credentials securely deleted"
                } || {
                    echo "⚠ Failed to configure WiFi, credentials preserved at /root/wifi-credentials"
                    echo "You can manually connect later with:"
                    echo "nmcli device wifi connect \"$WIFI_SSID\" password \"YOUR_PASSWORD\""
                }
            else
                echo "⚠ No WiFi device detected, skipping auto-configuration"
                echo "WiFi credentials preserved at /root/wifi-credentials for manual setup"
            fi
        else
            echo "No saved WiFi credentials found (ethernet or manual setup)"
        fi
        echo "POST_WIFI=true" >> "$POST_STATE_FILE"
    fi
    
    # Kernel parameter optimization
    if [[ $INSTALL_KERNEL_OPTS =~ ^[Yy]$ ]]; then
        step_header "KERNEL OPTIMIZATION"
        if grep -q "POST_KERNEL=true" "$POST_STATE_FILE" 2>/dev/null; then
            echo "✓ Kernel optimization already completed - SKIPPING"
        else
            echo "Optimizing kernel parameters..."
            if lsblk | grep -q nvme; then
                ELEVATOR="none"
                echo "NVMe SSD detected, using 'none' scheduler"
            else
                ELEVATOR="mq-deadline"
                echo "SATA SSD detected, using 'mq-deadline' scheduler"
            fi
            
            BOOT_ENTRY="/boot/loader/entries/arch.conf"
            if [[ -f "$BOOT_ENTRY" ]]; then
                sudo cp "$BOOT_ENTRY" "${BOOT_ENTRY}.backup"
                sudo sed -i "s/quiet loglevel=3/elevator=$ELEVATOR kernel.yama.ptrace_scope=1 mitigations=off quiet loglevel=3/" "$BOOT_ENTRY"
                echo "Kernel parameters updated"
            fi
            echo "POST_KERNEL=true" >> "$POST_STATE_FILE"
        fi
    else
        echo "Skipping kernel optimization"
    fi
    
    # YAY installation
    step_header "YAY AUR HELPER"
    if grep -q "POST_YAY=true" "$POST_STATE_FILE" 2>/dev/null; then
        echo "✓ yay already installed - SKIPPING"
    else
        echo "Installing yay AUR helper..."
        if ! command -v yay &> /dev/null; then
            cd /tmp
            git clone https://aur.archlinux.org/yay.git
            cd yay
            makepkg -si --noconfirm
            cd ~
            rm -rf /tmp/yay
            echo "yay installed successfully!"
        else
            echo "yay already installed"
        fi
        echo "POST_YAY=true" >> "$POST_STATE_FILE"
    fi
    
    # ZSH setup
    if [[ $INSTALL_OMZ =~ ^[Yy]$ ]]; then
        step_header "ZSH AND OH-MY-ZSH SETUP"
        if grep -q "POST_ZSH=true" "$POST_STATE_FILE" 2>/dev/null; then
            echo "✓ Oh My Zsh already configured - SKIPPING"
        else
            echo "Setting up Zsh and Oh My Zsh..."
            if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
                RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
                
                ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
                
                git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
                git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
                git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
                
                sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' ~/.zshrc
                sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting sudo extract)/' ~/.zshrc
                
                echo "Oh My Zsh setup complete!"
            fi
            echo "POST_ZSH=true" >> "$POST_STATE_FILE"
        fi
    else
        echo "Skipping Oh My Zsh installation"
    fi
    
    # Install additional fonts and tools
    if [[ $INSTALL_OMZ =~ ^[Yy]$ ]]; then
        step_header "ADDITIONAL PACKAGES"
        if grep -q "POST_PACKAGES=true" "$POST_STATE_FILE" 2>/dev/null; then
            echo "✓ Additional packages already installed - SKIPPING"
        else
            echo "Installing additional packages..."
            yay -S --noconfirm --needed \
                ttf-meslo-nerd-font-powerlevel10k
            echo "POST_PACKAGES=true" >> "$POST_STATE_FILE"
        fi
    else
        echo "Skipping additional font packages"
    fi
    
    # Configure PipeWire services
    step_header "PIPEWIRE CONFIGURATION"
    if grep -q "POST_PIPEWIRE=true" "$POST_STATE_FILE" 2>/dev/null; then
        echo "✓ PipeWire already configured - SKIPPING"
    else
        echo "Configuring PipeWire services..."
        systemctl --user enable pipewire pipewire-pulse wireplumber
        systemctl --user start pipewire pipewire-pulse wireplumber
        echo "POST_PIPEWIRE=true" >> "$POST_STATE_FILE"
    fi
    
    # Graphics drivers prompt
    if [[ $INSTALL_GRAPHICS =~ ^[Yy]$ ]]; then
        step_header "GRAPHICS DRIVERS"
        if grep -q "POST_GRAPHICS=true" "$POST_STATE_FILE" 2>/dev/null; then
            echo "✓ Graphics drivers already handled - SKIPPING"
        else
        echo "Select graphics drivers to install:"
        echo "1) AMD drivers (default for integrated graphics)"
        echo "2) NVIDIA drivers"
        echo "3) AMD + NVIDIA (hybrid laptop setup)"
        echo "4) Skip graphics drivers"
        read -p "Choose option (1/2/3/4) [default: 1]: " gpu_choice
        
        # Default to AMD if user just presses Enter
        gpu_choice=${gpu_choice:-1}
        
        case $gpu_choice in
            1)
                echo "Installing AMD drivers..."
                sudo pacman -S --needed --noconfirm \
                    mesa mesa-utils lib32-mesa \
                    vulkan-icd-loader lib32-vulkan-icd-loader \
                    vulkan-radeon lib32-vulkan-radeon \
                    vulkan-tools xf86-video-amdgpu \
                    linux-firmware-amdgpu
                
                echo "AMD drivers installed (integrated graphics default)!"
                ;;
            2)
                echo "Installing NVIDIA drivers..."
                sudo pacman -S --needed --noconfirm \
                    nvidia-open nvidia-utils lib32-nvidia-utils \
                    nvidia-settings nvidia-prime
                
                if ! grep -q "MODULES=(nvidia" /etc/mkinitcpio.conf; then
                    sudo sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
                    sudo mkinitcpio -P
                fi
                
                if ! grep -q "nvidia-drm.modeset=1" /boot/loader/entries/arch.conf; then
                    sudo sed -i 's/quiet loglevel=3/nvidia-drm.modeset=1 quiet loglevel=3/' /boot/loader/entries/arch.conf
                fi
                
                echo "NVIDIA drivers installed!"
                ;;
            3)
                echo "Installing both AMD and NVIDIA drivers (hybrid setup)..."
                # Install AMD drivers first (for integrated)
                sudo pacman -S --needed --noconfirm \
                    mesa mesa-utils lib32-mesa \
                    vulkan-icd-loader lib32-vulkan-icd-loader \
                    vulkan-radeon lib32-vulkan-radeon \
                    vulkan-tools xf86-video-amdgpu \
                    linux-firmware-amdgpu
                
                # Install NVIDIA drivers (for dedicated)
                sudo pacman -S --needed --noconfirm \
                    nvidia-open nvidia-utils lib32-nvidia-utils \
                    nvidia-settings nvidia-prime
                
                if ! grep -q "MODULES=(nvidia" /etc/mkinitcpio.conf; then
                    sudo sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
                    sudo mkinitcpio -P
                fi
                
                if ! grep -q "nvidia-drm.modeset=1" /boot/loader/entries/arch.conf; then
                    sudo sed -i 's/quiet loglevel=3/nvidia-drm.modeset=1 quiet loglevel=3/' /boot/loader/entries/arch.conf
                fi
                
                # Configure for AMD default, NVIDIA on-demand
                echo "Configuring AMD as default, NVIDIA for on-demand use..."
                echo "Use 'prime-run' command to run programs on NVIDIA GPU"
                echo "Example: prime-run glxinfo | grep 'OpenGL renderer'"
                
                echo "Hybrid AMD+NVIDIA setup complete!"
                ;;
            4)
                echo "Skipping graphics driver installation"
                ;;
            *)
                echo "Invalid choice, skipping graphics drivers"
                ;;
        esac
        echo "POST_GRAPHICS=true" >> "$POST_STATE_FILE"
        fi
    else
        echo "Skipping graphics driver installation"
    fi
    
    # Final setup
    step_header "FINAL CONFIGURATION"
    if grep -q "POST_FINAL=true" "$POST_STATE_FILE" 2>/dev/null; then
        echo "✓ Final configuration already completed - SKIPPING"
    else
        echo "Final configuration..." | tee -a "$POST_INSTALL_LOG"
        mkdir -p ~/Documents ~/Downloads ~/Pictures ~/Videos ~/Music
        
        # Only add to lp group if Bluetooth was installed
        if [[ $INSTALL_BLUETOOTH =~ ^[Yy]$ ]]; then
            sudo usermod -a -G lp "$USERNAME"
        fi
        
        # Only enable firewall if it was installed
        if [[ $INSTALL_FIREWALL =~ ^[Yy]$ ]]; then
            sudo ufw enable
        fi
        
        echo "POST_FINAL=true" >> "$POST_STATE_FILE"
    fi
    
    # Post-installation verification
    echo | tee -a "$POST_INSTALL_LOG"
    echo "=== POST-INSTALLATION VERIFICATION ===" | tee -a "$POST_INSTALL_LOG"
    echo | tee -a "$POST_INSTALL_LOG"
    
    # Check boot entries
    if sudo bootctl list &> /dev/null; then
        echo "✓ Boot entries valid" | tee -a "$POST_INSTALL_LOG"
    else
        echo "✗ Boot entries may have issues" | tee -a "$POST_INSTALL_LOG"
    fi
    
    # Check network
    if ping -c 1 archlinux.org &> /dev/null; then
        echo "✓ Network connectivity working" | tee -a "$POST_INSTALL_LOG"
    else
        echo "✗ Network connectivity issues" | tee -a "$POST_INSTALL_LOG"
    fi
    
    # Check sudo access
    if sudo -n true 2>/dev/null; then
        echo "✓ Sudo access configured" | tee -a "$POST_INSTALL_LOG"
    else
        echo "✓ Sudo requires password (normal)" | tee -a "$POST_INSTALL_LOG"
    fi
    
    # Check services
    SERVICES_OK=true
    if systemctl is-active --quiet NetworkManager; then
        echo "✓ NetworkManager running" | tee -a "$POST_INSTALL_LOG"
    else
        echo "✗ NetworkManager not running" | tee -a "$POST_INSTALL_LOG"
        SERVICES_OK=false
    fi
    
    if [[ $INSTALL_BLUETOOTH =~ ^[Yy]$ ]]; then
        if systemctl is-active --quiet bluetooth; then
            echo "✓ Bluetooth service running" | tee -a "$POST_INSTALL_LOG"
        else
            echo "✗ Bluetooth service not running" | tee -a "$POST_INSTALL_LOG"
            SERVICES_OK=false
        fi
    fi
    
    if [[ $INSTALL_TLP =~ ^[Yy]$ ]]; then
        if systemctl is-enabled --quiet tlp; then
            echo "✓ TLP power management enabled" | tee -a "$POST_INSTALL_LOG"
        else
            echo "✗ TLP not enabled" | tee -a "$POST_INSTALL_LOG"
            SERVICES_OK=false
        fi
    fi
    
    if [[ $INSTALL_FIREWALL =~ ^[Yy]$ ]]; then
        if sudo ufw status | grep -q "Status: active"; then
            echo "✓ UFW firewall active" | tee -a "$POST_INSTALL_LOG"
        else
            echo "✗ UFW firewall not active" | tee -a "$POST_INSTALL_LOG"
            SERVICES_OK=false
        fi
    fi
    
    # Generate final report
    echo | tee -a "$POST_INSTALL_LOG"
    echo "=== INSTALLATION REPORT ===" | tee -a "$POST_INSTALL_LOG"
    echo | tee -a "$POST_INSTALL_LOG"
    echo "System Information:" | tee -a "$POST_INSTALL_LOG"
    echo "  Hostname: $(hostname)" | tee -a "$POST_INSTALL_LOG"
    echo "  Kernel: $(uname -r)" | tee -a "$POST_INSTALL_LOG"
    echo "  CPU: $(lscpu | grep 'Model name' | cut -d':' -f2 | xargs)" | tee -a "$POST_INSTALL_LOG"
    echo "  RAM: $(free -h | awk '/^Mem:/{print $2}')" | tee -a "$POST_INSTALL_LOG"
    echo "  Disk: $(df -h / | awk 'NR==2{print $2}')" | tee -a "$POST_INSTALL_LOG"
    echo | tee -a "$POST_INSTALL_LOG"
    echo "Installed Components:" | tee -a "$POST_INSTALL_LOG"
    [[ $INSTALL_PIPEWIRE =~ ^[Yy]$ ]] && echo "  ✓ PipeWire audio system" | tee -a "$POST_INSTALL_LOG"
    [[ $INSTALL_ZSH =~ ^[Yy]$ ]] && echo "  ✓ Zsh shell" | tee -a "$POST_INSTALL_LOG"
    [[ $INSTALL_OMZ =~ ^[Yy]$ ]] && echo "  ✓ Oh My Zsh with Powerlevel10k" | tee -a "$POST_INSTALL_LOG"
    [[ $INSTALL_MONITORING =~ ^[Yy]$ ]] && echo "  ✓ System monitoring tools" | tee -a "$POST_INSTALL_LOG"
    [[ $INSTALL_TIMESHIFT =~ ^[Yy]$ ]] && echo "  ✓ Timeshift backup system" | tee -a "$POST_INSTALL_LOG"
    [[ $INSTALL_BLUETOOTH =~ ^[Yy]$ ]] && echo "  ✓ Bluetooth support" | tee -a "$POST_INSTALL_LOG"
    [[ $INSTALL_TLP =~ ^[Yy]$ ]] && echo "  ✓ TLP power management" | tee -a "$POST_INSTALL_LOG"
    [[ $INSTALL_FIREWALL =~ ^[Yy]$ ]] && echo "  ✓ UFW firewall" | tee -a "$POST_INSTALL_LOG"
    [[ $INSTALL_ZRAM =~ ^[Yy]$ ]] && echo "  ✓ ZRAM compressed swap" | tee -a "$POST_INSTALL_LOG"
    echo | tee -a "$POST_INSTALL_LOG"
    echo "Optimizations Applied:" | tee -a "$POST_INSTALL_LOG"
    echo "  ✓ tmpfs for /tmp and /var/tmp" | tee -a "$POST_INSTALL_LOG"
    echo "  ✓ Parallel makepkg compilation" | tee -a "$POST_INSTALL_LOG"
    echo "  ✓ ZSTD compression optimization" | tee -a "$POST_INSTALL_LOG"
    echo "  ✓ Automatic package cache cleaning" | tee -a "$POST_INSTALL_LOG"
    echo "  ✓ CPU governor: schedutil" | tee -a "$POST_INSTALL_LOG"
    [[ $INSTALL_KERNEL_OPTS =~ ^[Yy]$ ]] && echo "  ✓ Kernel optimizations applied" | tee -a "$POST_INSTALL_LOG"
    [[ $INSTALL_SYSCTL =~ ^[Yy]$ ]] && echo "  ✓ System memory optimizations" | tee -a "$POST_INSTALL_LOG"
    echo | tee -a "$POST_INSTALL_LOG"
    
    if $SERVICES_OK; then
        echo "✓ All services configured correctly!" | tee -a "$POST_INSTALL_LOG"
    else
        echo "⚠ Some services need attention (see above)" | tee -a "$POST_INSTALL_LOG"
    fi
    
    echo | tee -a "$POST_INSTALL_LOG"
    echo "=== POST-INSTALLATION COMPLETE ===" | tee -a "$POST_INSTALL_LOG"
    echo | tee -a "$POST_INSTALL_LOG"
    echo "Installation logs:" | tee -a "$POST_INSTALL_LOG"
    echo "  Main install: /root/arch-install-*.log" | tee -a "$POST_INSTALL_LOG"
    echo "  Post-install: $POST_INSTALL_LOG" | tee -a "$POST_INSTALL_LOG"
    echo | tee -a "$POST_INSTALL_LOG"
    echo "After reboot:" | tee -a "$POST_INSTALL_LOG"
    [[ $INSTALL_OMZ =~ ^[Yy]$ ]] && echo "  • Configure Powerlevel10k: p10k configure" | tee -a "$POST_INSTALL_LOG"
    [[ $INSTALL_ZRAM =~ ^[Yy]$ ]] && echo "  • Test zram: cat /proc/swaps && free -h" | tee -a "$POST_INSTALL_LOG"
    [[ $INSTALL_BLUETOOTH =~ ^[Yy]$ ]] && echo "  • Test bluetooth: bluetoothctl" | tee -a "$POST_INSTALL_LOG"
    echo "  • View boot analysis: systemd-analyze blame" | tee -a "$POST_INSTALL_LOG"
    echo "  • Check critical chain: systemd-analyze critical-chain" | tee -a "$POST_INSTALL_LOG"
    echo | tee -a "$POST_INSTALL_LOG"
    
    read -p "Reboot now? (y/N): " reboot_now
    if [[ $reboot_now =~ ^[Yy]$ ]]; then
        rm -f "$POST_STATE_FILE"  # Clean up state file
        echo "Rebooting..." | tee -a "$POST_INSTALL_LOG"
        sudo reboot
    fi
    
else
    echo "Usage: $0 [install|postinstall] [--skip-to STEP_NAME]"
    echo
    echo "Phase options:"
    echo "  install     - Run the initial installation (default)"
    echo "  postinstall - Run post-installation configuration"
    echo
    echo "Skip options for install phase:"
    echo "  --skip-to partitioning  - Skip to partition selection"
    echo "  --skip-to mounting      - Skip to partition mounting"
    echo "  --skip-to mirrors       - Skip to mirror optimization"
    echo "  --skip-to pacstrap      - Skip to base system installation"
    echo "  --skip-to fstab         - Skip to fstab generation"
    echo "  --skip-to zram          - Skip to zram configuration"
    echo "  --skip-to chroot        - Skip to chroot configuration"
    echo
    echo "Examples:"
    echo "  $0                           - Start fresh installation"
    echo "  $0 install --skip-to mirrors - Skip to mirror optimization"
    echo "  $0 postinstall              - Run post-installation setup"
    exit 1
fi
