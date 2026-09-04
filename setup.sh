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