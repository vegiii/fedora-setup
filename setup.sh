#!/bin/bash

# ============================================================================
# initialization
# ============================================================================

set -eE

# Use colours only when writing to a terminal.
log() {
    local colour=$1 label=$2 message=$3
    if [[ -t 1 && ${TERM:-dumb} != dumb && -z ${NO_COLOR+x} ]]; then
        printf '\033[%sm[%s] %s\033[0m\n' "$colour" "$label" "$message"
    else
        printf '[%s] %s\n' "$label" "$message"
    fi
}

section() { printf '\n'; log '1;34' SECTION "=== $1 ==="; }
info() { log 36 INFO "$1"; }
success() { log 32 OK "$1"; }
notice() { log 33 NOTICE "$1"; }
error() { log 31 ERROR "$1" >&2; }

report_error() {
    local status=$1 line=$2
    error "Setup failed at line $line (exit status $status)."
    exit "$status"
}
trap 'report_error "$?" "$LINENO"' ERR

# Check that the script is running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root. Try: sudo $0"
    exit 1
fi

# Find the home directory of the user who invoked sudo
USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

# ============================================================================
# SYSTEM SETUP
# ============================================================================

section "SYSTEM SETUP"
# Set hostname
info "Setting hostname to fedora..."
hostnamectl set-hostname fedora
success "Hostname configured."

# Optimize DNF
info "Configuring DNF download settings..."
grep -q '^max_parallel_downloads=' /etc/dnf/dnf.conf || \
    echo 'max_parallel_downloads=10' >> /etc/dnf/dnf.conf

grep -q '^fastestmirror=' /etc/dnf/dnf.conf || \
    echo 'fastestmirror=True' >> /etc/dnf/dnf.conf

grep -q '^defaultyes=' /etc/dnf/dnf.conf || \
    echo 'defaultyes=True' >> /etc/dnf/dnf.conf
success "DNF settings configured."

# Install firmware updates
info "Checking for and applying firmware updates..."
# Exit code 2 means there is nothing to do (common in VMs)
fwupdmgr refresh --force || [[ $? -eq 2 ]]
fwupdmgr update --assume-yes || [[ $? -eq 2 ]]
success "Firmware update checks completed."

# ============================================================================
# SOFTWARE SOURCES
# ============================================================================

section "SOFTWARE SOURCES"
# Install DNF repository tools
info "Installing DNF repository tools..."
dnf install -y dnf5-plugins
success "DNF repository tools installed."

# Enable RPM Fusion
info "Enabling RPM Fusion repositories..."
dnf install -y \
    "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
success "RPM Fusion repositories enabled."

# Enable Terra using its signing key for package verification
info "Enabling Terra with signature verification..."
dnf install -y \
    --repofrompath 'terra-bootstrap,https://repos.fyralabs.com/terra$releasever' \
    --setopt='terra-bootstrap.gpgcheck=1' \
    --setopt="terra-bootstrap.gpgkey=https://repos.fyralabs.com/terra$(rpm -E %fedora)/key.asc" \
    terra-release terra-gpg-keys
success "Terra repository enabled."

# Install Flatpak and configure Flathub
info "Installing Flatpak and configuring Flathub..."
dnf install -y flatpak
flatpak remote-add --if-not-exists \
    flathub https://dl.flathub.org/repo/flathub.flatpakrepo
success "Flatpak and Flathub configured."

# ============================================================================
# SOFTWARE INSTALLATION
# ============================================================================

section "SOFTWARE INSTALLATION"
# Install DNF applications
info "Installing KDE Plasma and DNF applications..."
DNF_PACKAGES=(
    # Core KDE Plasma
    plasma-desktop
    plasma-login-manager
    kscreen
    konsole
    dolphin
    kwrite

    # KDE components
    plasma-nm
    bluedevil
    kio-admin
    kde-gtk-config
    kio-extras
    plasma-discover-flatpak
    libappindicator-gtk3
    libayatana-appindicator-gtk3
    langpacks-nb
    pam-kwallet
    plasma-workspace-wallpapers
    bash-color-prompt
    papirus-icon-theme

    # System and CLI tools
    btop
    rsync
    tree
    wget
    curl
    micro
    lm_sensors
    fastfetch

    # KDE applications
    ark
    okular
    kcalc
    haruna
    filelight
    gwenview
    spectacle
    plasma-discover
    kde-partitionmanager

    # Applications
    firefox
    steam
    mangohud
    discord
)

dnf install -y "${DNF_PACKAGES[@]}"
success "KDE Plasma and DNF applications installed."

# Install Microsoft Core Fonts from Terra
info "Installing Microsoft Core Fonts..."
dnf install -y ms-core-fonts
success "Microsoft Core Fonts installed."

# Install Google Chrome
info "Configuring the Google Chrome repository and installing Chrome..."
dnf install -y fedora-workstation-repositories
dnf config-manager setopt google-chrome.enabled=1
dnf install -y google-chrome-stable
success "Google Chrome installed."

# Install Visual Studio Code and verify the Microsoft signing key
info "Configuring the VS Code repository, importing its signing key and installing VS Code..."
if [[ ! -f /etc/yum.repos.d/config.repo ]]; then
    dnf config-manager addrepo \
        --from-repofile=https://packages.microsoft.com/yumrepos/vscode/config.repo
fi
rpm --import https://packages.microsoft.com/keys/microsoft.asc
dnf config-manager setopt vscode-yum.gpgcheck=1 \
    vscode-yum.gpgkey=https://packages.microsoft.com/keys/microsoft.asc
dnf install -y code
success "Visual Studio Code installed."

# Install App Grid
info "Enabling the App Grid repository and installing App Grid..."
dnf copr enable -y scujas/plasma-applet-appgrid
dnf install -y plasma-applet-appgrid
success "App Grid installed."

# Install DNF groups
info "Installing multimedia and virtualization groups..."
dnf install -y @multimedia @virtualization
success "DNF groups installed."

# Install Flatpak applications
info "Installing Flatpak applications from Flathub..."
FLATPAK_APPS=(
    com.spotify.Client
    md.obsidian.Obsidian
    net.nokyan.Resources
    org.onlyoffice.desktopeditors
    it.mijorus.gearlever
    com.github.tchx84.Flatseal
    com.vysp3r.ProtonPlus
    org.prismlauncher.PrismLauncher
    xyz.z3ntu.razergenie
)

flatpak install -y flathub "${FLATPAK_APPS[@]}"
success "Flatpak applications installed."

# ============================================================================
# CONFIGURATION
# ============================================================================

section "CONFIGURATION"
# Set the Plymouth boot splash theme and rebuild the initramfs
info "Setting the Plymouth theme and rebuilding the initramfs..."
dnf install -y plymouth-theme-spinner
plymouth-set-default-theme spinner -R
success "Plymouth theme configured and initramfs rebuilt."

# Configure GRUB and rebuild its configuration
info "Configuring GRUB and rebuilding its configuration..."
sed -i 's/^GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=true/' /etc/default/grub
grep -q '^GRUB_SAVEDEFAULT=' /etc/default/grub || \
    echo 'GRUB_SAVEDEFAULT=true' >> /etc/default/grub
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' /etc/default/grub
grep -q '^GRUB_TIMEOUT=' /etc/default/grub || \
    echo 'GRUB_TIMEOUT=2' >> /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg
success "GRUB configured."

# Set the system language and 24-hour time format
info "Setting the system language and 24-hour time format..."
localectl set-locale LANG=en_US.UTF-8 LC_TIME=nb_NO.UTF-8
success "Language and time format configured."

# Configure AC power settings as the user to preserve file ownership
info "Configuring KDE AC power settings for $SUDO_USER..."
runuser -u "$SUDO_USER" -- mkdir -p "$USER_HOME/.config"
runuser -u "$SUDO_USER" -- kwriteconfig6 --file "$USER_HOME/.config/powerdevilrc" \
    --group AC --group Display --key DimDisplayIdleTimeoutSec -- -1
runuser -u "$SUDO_USER" -- kwriteconfig6 --file "$USER_HOME/.config/powerdevilrc" \
    --group AC --group Display --key DimDisplayWhenIdle false
runuser -u "$SUDO_USER" -- kwriteconfig6 --file "$USER_HOME/.config/powerdevilrc" \
    --group AC --group Display --key TurnOffDisplayIdleTimeoutSec 600
runuser -u "$SUDO_USER" -- kwriteconfig6 --file "$USER_HOME/.config/powerdevilrc" \
    --group AC --group SuspendAndShutdown --key AutoSuspendIdleTimeoutSec 10800
success "KDE AC power settings configured."

# Mount the NAS storage share automatically when accessed
info "Configuring automatic mounting of the NAS share..."
mkdir -p /mnt/storage
grep -qF '192.168.50.20:/media/storage /mnt/storage nfs defaults,_netdev,nofail,x-systemd.automount 0 0' /etc/fstab || \
    echo '192.168.50.20:/media/storage /mnt/storage nfs defaults,_netdev,nofail,x-systemd.automount 0 0' >> /etc/fstab
success "NAS automount configured."

# Rename the root Btrfs filesystem
info "Setting the root Btrfs filesystem label to fedora..."
btrfs filesystem label / fedora
success "Root Btrfs filesystem label configured."

# Offer to reboot after setup completes
success "Setup completed successfully."
if read -r -p "Setup complete. Reboot now? [Y/n] " REBOOT_REPLY &&
    [[ -z $REBOOT_REPLY || ${REBOOT_REPLY,,} == y || ${REBOOT_REPLY,,} == yes ]]; then
    info "Rebooting..."
    systemctl reboot
else
    notice "Reboot skipped. You can reboot later to apply all changes."
fi
