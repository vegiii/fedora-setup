#!/bin/bash

# ============================================================================
# INITIALIZATION
# ============================================================================

set -eE

# Track total setup time
SECONDS=0

# Terminal output
log() {
    local colour=$1 message=$2
    printf '\033[%sm%s\033[0m\n' "$colour" "$message"
}

section() { printf '\n'; log '1;34' "=== $1 ==="; }          # Bold blue
info() { log '1;33' "$1"; }                                  # Bold yellow
success() { log '1;36' "$1"; }                               # Bold cyan
error() { log '1;31' "[ERROR] $1" >&2; }                     # Bold red

# Error handling
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

# Configure DNF
info "Configuring DNF settings..."
grep -q '^max_parallel_downloads=' /etc/dnf/dnf.conf || \
    echo 'max_parallel_downloads=10' >> /etc/dnf/dnf.conf

grep -q '^fastestmirror=' /etc/dnf/dnf.conf || \
    echo 'fastestmirror=True' >> /etc/dnf/dnf.conf

grep -q '^defaultyes=' /etc/dnf/dnf.conf || \
    echo 'defaultyes=True' >> /etc/dnf/dnf.conf
success "DNF settings configured."

# Install firmware updates
info "Checking for and applying firmware updates..."
fwupdmgr refresh --force || [[ $? -eq 2 ]]
fwupdmgr update --assume-yes || [[ $? -eq 2 ]]
success "Firmware update checks completed."

# ============================================================================
# SOFTWARE SOURCES
# ============================================================================

section "SOFTWARE SOURCES"
# Enable RPM Fusion
info "Enabling RPM Fusion repositories..."
dnf install -y \
    "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
success "RPM Fusion repositories enabled."

# Enable Terra repository
info "Enabling Terra repository..."
dnf install -y \
    --repofrompath 'terra-bootstrap,https://repos.fyralabs.com/terra$releasever' \
    --setopt='terra-bootstrap.gpgcheck=1' \
    --setopt="terra-bootstrap.gpgkey=https://repos.fyralabs.com/terra$(rpm -E %fedora)/key.asc" \
    terra-release terra-gpg-keys
success "Terra repository enabled."

# Install Flatpak, remove the Fedora remote and configure Flathub
info "Installing Flatpak and configuring Flathub..."
dnf install -y flatpak
if flatpak remotes --system --columns=name | grep -qx fedora; then
    flatpak remote-delete --system fedora
fi
flatpak remote-add --if-not-exists \
    flathub https://dl.flathub.org/repo/flathub.flatpakrepo
success "Flatpak and Flathub configured."

# ============================================================================
# SOFTWARE INSTALLATION
# ============================================================================

section "SOFTWARE INSTALLATION"
# Install DNF packages
info "Installing DNF packages..."
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
    plasma-lookandfeel-fedora

    # System tools
    gh
    btop
    rsync
    tree
    wget
    micro
    acl
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
success "DNF packages installed."

# Install DNF groups
info "Installing multimedia and virtualization groups..."
dnf install -y @multimedia @virtualization
success "DNF groups installed."

# Install Microsoft Core Fonts from Terra
info "Installing Microsoft Core Fonts..."
dnf install -y ms-core-fonts
success "Microsoft Core Fonts installed."

# Install Google Chrome
info "Enabling the Google Chrome repository and installing Chrome..."
dnf install -y fedora-workstation-repositories
dnf config-manager setopt google-chrome.enabled=1
dnf install -y google-chrome-stable
success "Google Chrome installed."

# Install ChatGPT
info "Installing ChatGPT..."
dnf install -y \
    https://persistent.oaistatic.com/codex-app-prod/linux/rpm/latest/chatgpt.x86_64.rpm
success "ChatGPT installed."

# Install Visual Studio Code
info "Enabling the VS Code repository and installing VS Code..."
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

# Install the OpenRazer driver
info "Installing OpenRazer..."
dnf install -y kernel-devel
if [[ ! -f /etc/yum.repos.d/hardware:razer.repo ]]; then
    dnf config-manager addrepo \
        --from-repofile=https://openrazer.github.io/hardware:razer.repo
fi
dnf install -y openrazer-meta
usermod -aG plugdev "$SUDO_USER"
success "OpenRazer installed and $SUDO_USER added to plugdev."

# Install Flatpak applications
info "Installing Flatpak applications..."
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
info "Configuring Plymouth theme..."
dnf install -y plymouth-theme-spinner
plymouth-set-default-theme spinner -R

# Configure GRUB and rebuild its configuration
info "Configuring GRUB and rebuilding its configuration..."
sed -i 's/^GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=true/' /etc/default/grub
grep -q '^GRUB_SAVEDEFAULT=' /etc/default/grub || \
    echo 'GRUB_SAVEDEFAULT=true' >> /etc/default/grub
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' /etc/default/grub
grep -q '^GRUB_TIMEOUT=' /etc/default/grub || \
    echo 'GRUB_TIMEOUT=2' >> /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg

# Increase the per-user inotify instance limit
info "Setting the inotify instance limit to 512..."
echo 'fs.inotify.max_user_instances = 512' > /etc/sysctl.d/90-inotify.conf
sysctl -p /etc/sysctl.d/90-inotify.conf

# Set the system language and 24-hour time format
info "Setting the system language and 24-hour time format..."
localectl set-locale LANG=en_US.UTF-8 LC_TIME=nb_NO.UTF-8

# Configure Plasma appearance at the next desktop login
info "Configuring Fedora Dark, Papirus icons and wallpaper..."
runuser -u "$SUDO_USER" -- mkdir -p "$USER_HOME/.local/bin" "$USER_HOME/.config/autostart"
runuser -u "$SUDO_USER" -- tee "$USER_HOME/.local/bin/setup-plasma-appearance.sh" > /dev/null <<'EOF'
#!/bin/bash
set -e

# Apply the global theme before overriding its icons and wallpaper
plasma-apply-lookandfeel -a org.fedoraproject.fedoradark.desktop
/usr/libexec/plasma-changeicons Papirus
plasma-apply-wallpaperimage /usr/share/wallpapers/DarkestHour/contents/images/2560x1600.jpg

# Stop running at login once all settings have been applied
rm -- "$HOME/.config/autostart/setup-plasma-appearance.desktop" "$0"
EOF
runuser -u "$SUDO_USER" -- tee "$USER_HOME/.config/autostart/setup-plasma-appearance.desktop" > /dev/null <<EOF
[Desktop Entry]
Type=Application
Name=Set up Plasma appearance
Exec=/bin/bash "$USER_HOME/.local/bin/setup-plasma-appearance.sh"
OnlyShowIn=KDE;
Terminal=false
X-KDE-autostart-after=panel
EOF

# Set the lock screen and login screen wallpaper before the first login
info "Setting the lock screen and login screen wallpaper..."
runuser -u "$SUDO_USER" -- kwriteconfig6 --file "$USER_HOME/.config/kscreenlockerrc" \
    --group Greeter --key WallpaperPlugin org.kde.image
runuser -u "$SUDO_USER" -- kwriteconfig6 --file "$USER_HOME/.config/kscreenlockerrc" \
    --group Greeter --group Wallpaper --group org.kde.image --group General \
    --key Image file:///usr/share/wallpapers/DarkestHour/
kwriteconfig6 --file /etc/plasmalogin.conf \
    --group Greeter --key WallpaperPlugin org.kde.image
kwriteconfig6 --file /etc/plasmalogin.conf \
    --group Greeter --group Wallpaper --group org.kde.image --group General \
    --key Image file:///usr/share/wallpapers/DarkestHour/

# Configure Plasma power management as the user to preserve file ownership
info "Configuring Plasma power management for $SUDO_USER..."
runuser -u "$SUDO_USER" -- mkdir -p "$USER_HOME/.config"
runuser -u "$SUDO_USER" -- kwriteconfig6 --file "$USER_HOME/.config/powerdevilrc" \
    --group AC --group Display --key DimDisplayIdleTimeoutSec -- -1
runuser -u "$SUDO_USER" -- kwriteconfig6 --file "$USER_HOME/.config/powerdevilrc" \
    --group AC --group Display --key DimDisplayWhenIdle false
runuser -u "$SUDO_USER" -- kwriteconfig6 --file "$USER_HOME/.config/powerdevilrc" \
    --group AC --group Display --key TurnOffDisplayIdleTimeoutSec 600
runuser -u "$SUDO_USER" -- kwriteconfig6 --file "$USER_HOME/.config/powerdevilrc" \
    --group AC --group SuspendAndShutdown --key AutoSuspendAction 1
runuser -u "$SUDO_USER" -- kwriteconfig6 --file "$USER_HOME/.config/powerdevilrc" \
    --group AC --group SuspendAndShutdown --key AutoSuspendIdleTimeoutSec 10800

# Configure libvirt storage pools
info "Configuring libvirt storage pools..."
runuser -u "$SUDO_USER" -- mkdir -p "$USER_HOME/VMs/Images" "$USER_HOME/VMs/ISOs"

# Allow system QEMU to access VM storage inside the user's home
setfacl -m u:qemu:--x "$USER_HOME" "$USER_HOME/VMs"
setfacl -m u:qemu:r-x "$USER_HOME/VMs/Images" "$USER_HOME/VMs/ISOs"
semanage fcontext -a -t virt_image_t "$USER_HOME/VMs(/.*)?"
restorecon -R "$USER_HOME/VMs"

# Remove Fedora's default pool if present
if virsh --connect qemu:///system pool-list --name | grep -qx default; then
    virsh --connect qemu:///system pool-destroy default
fi
if virsh --connect qemu:///system pool-info default > /dev/null 2>&1; then
    virsh --connect qemu:///system pool-undefine default
fi

virsh --connect qemu:///system pool-define-as default dir --target "$USER_HOME/VMs/Images"
virsh --connect qemu:///system pool-define-as ISOs dir --target "$USER_HOME/VMs/ISOs"
for pool in default ISOs; do
    virsh --connect qemu:///system pool-autostart "$pool"
    virsh --connect qemu:///system pool-start "$pool"
done

# Mount the NAS storage share automatically when accessed
info "Configuring automatic mounting of the NAS share..."
mkdir -p /mnt/storage
grep -qF '192.168.50.20:/media/storage /mnt/storage nfs defaults,_netdev,nofail,x-systemd.automount 0 0' /etc/fstab || \
    echo '192.168.50.20:/media/storage /mnt/storage nfs defaults,_netdev,nofail,x-systemd.automount 0 0' >> /etc/fstab

# Set the root filesystem label
info "Setting the root filesystem label to fedora..."
btrfs filesystem label / fedora

# Boot into the graphical desktop by default
info "Setting graphical boot as default..."
systemctl set-default graphical.target

# Show asterisks when entering a sudo password
info "Enabling sudo password feedback..."
echo 'Defaults pwfeedback' > /etc/sudoers.d/pwfeedback
chmod 0440 /etc/sudoers.d/pwfeedback
visudo -cf /etc/sudoers.d/pwfeedback

success "Configuration complete."

# Offer to reboot after setup completes
elapsed=$SECONDS
success "Setup completed successfully. ($((elapsed / 60))min, $((elapsed % 60))sec)"
info "Reboot now? [Y/n]"
if read -r REBOOT_REPLY &&
    [[ -z $REBOOT_REPLY || ${REBOOT_REPLY,,} == y || ${REBOOT_REPLY,,} == yes ]]; then
    info "Rebooting..."
    systemctl reboot
else
    info "Reboot skipped. You can reboot later to apply all changes."
fi
