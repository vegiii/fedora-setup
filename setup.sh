#!/bin/bash

# ============================================================================
# initialization
# ============================================================================

set -e

# Check that the script is running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Try: sudo $0"
    exit 1
fi

# Find the home directory of the user who invoked sudo
USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

# ============================================================================
# SYSTEM SETUP
# ============================================================================

# Set hostname
hostnamectl set-hostname fedora

# Optimize DNF
grep -q '^max_parallel_downloads=' /etc/dnf/dnf.conf || \
    echo 'max_parallel_downloads=10' >> /etc/dnf/dnf.conf

grep -q '^fastestmirror=' /etc/dnf/dnf.conf || \
    echo 'fastestmirror=True' >> /etc/dnf/dnf.conf

grep -q '^defaultyes=' /etc/dnf/dnf.conf || \
    echo 'defaultyes=True' >> /etc/dnf/dnf.conf

# Install firmware updates
# Exit code 2 means there is nothing to do (common in VMs)
fwupdmgr refresh --force || [[ $? -eq 2 ]]
fwupdmgr update --assume-yes || [[ $? -eq 2 ]]

# ============================================================================
# SOFTWARE SOURCES
# ============================================================================

# Install DNF repository tools
dnf install -y dnf5-plugins

# Enable RPM Fusion
dnf install -y \
    "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

# Enable Terra using its signing key for package verification
dnf install -y \
    --repofrompath 'terra-bootstrap,https://repos.fyralabs.com/terra$releasever' \
    --setopt='terra-bootstrap.gpgcheck=1' \
    --setopt="terra-bootstrap.gpgkey=https://repos.fyralabs.com/terra$(rpm -E %fedora)/key.asc" \
    terra-release terra-gpg-keys

# Install Flatpak and configure Flathub
dnf install -y flatpak
flatpak remote-add --if-not-exists \
    flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# ============================================================================
# SOFTWARE INSTALLATION
# ============================================================================

# Install DNF applications
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

# Install Microsoft Core Fonts from Terra
dnf install -y ms-core-fonts

# Install Google Chrome
dnf install -y fedora-workstation-repositories
dnf config-manager setopt google-chrome.enabled=1
dnf install -y google-chrome-stable

# Install Visual Studio Code and verify the Microsoft signing key
if [[ ! -f /etc/yum.repos.d/config.repo ]]; then
    dnf config-manager addrepo \
        --from-repofile=https://packages.microsoft.com/yumrepos/vscode/config.repo
fi
rpm --import https://packages.microsoft.com/keys/microsoft.asc
dnf config-manager setopt vscode-yum.gpgcheck=1 \
    vscode-yum.gpgkey=https://packages.microsoft.com/keys/microsoft.asc
dnf install -y code

# Install App Grid
dnf copr enable -y scujas/plasma-applet-appgrid
dnf install -y plasma-applet-appgrid

# Install DNF groups
dnf install -y @multimedia @virtualization

# Install Flatpak applications
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

# ============================================================================
# CONFIGURATION
# ============================================================================

# Set the Plymouth boot splash theme and rebuild the initramfs
dnf install -y plymouth-theme-spinner
plymouth-set-default-theme spinner -R

# Configure GRUB and rebuild its configuration
sed -i 's/^GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=true/' /etc/default/grub
grep -q '^GRUB_SAVEDEFAULT=' /etc/default/grub || \
    echo 'GRUB_SAVEDEFAULT=true' >> /etc/default/grub
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' /etc/default/grub
grep -q '^GRUB_TIMEOUT=' /etc/default/grub || \
    echo 'GRUB_TIMEOUT=2' >> /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg

# Set the system language and 24-hour time format
localectl set-locale LANG=en_US.UTF-8 LC_TIME=nb_NO.UTF-8

# Configure AC power settings as the user to preserve file ownership
runuser -u "$SUDO_USER" -- mkdir -p "$USER_HOME/.config"
runuser -u "$SUDO_USER" -- kwriteconfig6 --file "$USER_HOME/.config/powerdevilrc" \
    --group AC --group Display --key DimDisplayIdleTimeoutSec -- -1
runuser -u "$SUDO_USER" -- kwriteconfig6 --file "$USER_HOME/.config/powerdevilrc" \
    --group AC --group Display --key DimDisplayWhenIdle false
runuser -u "$SUDO_USER" -- kwriteconfig6 --file "$USER_HOME/.config/powerdevilrc" \
    --group AC --group Display --key TurnOffDisplayIdleTimeoutSec 600
runuser -u "$SUDO_USER" -- kwriteconfig6 --file "$USER_HOME/.config/powerdevilrc" \
    --group AC --group SuspendAndShutdown --key AutoSuspendIdleTimeoutSec 10800

# Mount the NAS storage share automatically when accessed
mkdir -p /mnt/storage
grep -qF '192.168.50.20:/media/storage /mnt/storage nfs defaults,_netdev,nofail,x-systemd.automount 0 0' /etc/fstab || \
    echo '192.168.50.20:/media/storage /mnt/storage nfs defaults,_netdev,nofail,x-systemd.automount 0 0' >> /etc/fstab

# Rename the root Btrfs filesystem
btrfs filesystem label / fedora

# Offer to reboot after setup completes
if read -r -p "Setup complete. Reboot now? [Y/n] " REBOOT_REPLY &&
    [[ -z $REBOOT_REPLY || ${REBOOT_REPLY,,} == y || ${REBOOT_REPLY,,} == yes ]]; then
    systemctl reboot
else
    echo "Reboot skipped. You can reboot later to apply all changes."
fi
