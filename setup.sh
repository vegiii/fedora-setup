#!/bin/bash

set -e

# Check that the script is running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Try: sudo $0"
    exit 1
fi

# System setup

# Set hostname
hostnamectl set-hostname fedora

# Optimize DNF
grep -q '^max_parallel_downloads=' /etc/dnf/dnf.conf || \
    echo 'max_parallel_downloads=10' >> /etc/dnf/dnf.conf

grep -q '^fastestmirror=' /etc/dnf/dnf.conf || \
    echo 'fastestmirror=True' >> /etc/dnf/dnf.conf

grep -q '^defaultyes=' /etc/dnf/dnf.conf || \
    echo 'defaultyes=True' >> /etc/dnf/dnf.conf

# Enable RPM Fusion
dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

# Configure Flathub
flatpak remote-add --if-not-exists \
    flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Install firmware updates
fwupdmgr refresh
fwupdmgr update

# Install DNF groups
dnf install -y @multimedia @virtualization

# Install Microsoft Core Fonts
dnf install -y curl cabextract xorg-x11-font-utils fontconfig
dnf install -y \
    https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm

# Install Papirus icon theme
dnf install -y papirus-icon-theme

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
    discord
    steam
    firefox
    dolphin
    kwrite
    mangohud
    haruna
    gwenview
    okular
    ark
    spectacle
    kcalc
    filelight
    plasma-discover
    kde-partitionmanager

    # KDE components
    plasma-nm
    bluedevil
    kio-admin
    kde-gtk-config
    kio-extras
    plasma-discover-flatpak
    libappindicator-gtk3
    langpacks-nb
    pam-kwallet
    plasma-workspace-wallpapers
    bash-color-prompt
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