#!/bin/bash

set -e

# Check that the script is running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Try: sudo $0"
    exit 1
fi

# Identify the user whose KDE settings will be configured
if [[ -z ${SUDO_USER:-} || $SUDO_USER == root ]]; then
    echo "Run this script with sudo from your user account."
    exit 1
fi
USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

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
fwupdmgr refresh --force
fwupdmgr get-updates
fwupdmgr update --assume-yes

# Enable RPM Fusion
dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

# Configure Flathub
flatpak remote-add --if-not-exists \
    flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Install Microsoft Core Fonts
dnf install -y curl cabextract xorg-x11-font-utils fontconfig
dnf install -y \
    https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm

# Install DNF repository tools
dnf install -y dnf-plugins-core

# Install Google Chrome
if [[ ! -f /etc/yum.repos.d/google-chrome.repo ]]; then
    dnf config-manager --add-repo \
        https://dl.google.com/linux/chrome/rpm/stable/x86_64/google-chrome.repo
fi
dnf install -y google-chrome-stable

# Install Visual Studio Code
if [[ ! -f /etc/yum.repos.d/config.repo ]]; then
    dnf config-manager --add-repo \
        https://packages.microsoft.com/yumrepos/vscode/config.repo
fi
dnf install -y code

# Install App Grid
dnf copr enable -y scujas/plasma-applet-appgrid
dnf install -y plasma-applet-appgrid

# Install DNF groups
dnf install -y @multimedia @virtualization

# Install DNF applications
DNF_PACKAGES=(
    # System and CLI tools
    btop
    rsync
    tree
    wget
    curl
    micro
    lm_sensors
    fastfetch

    # Applications
    firefox
    steam
    mangohud
    discord
    haruna
    gwenview


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

# Configuration

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
