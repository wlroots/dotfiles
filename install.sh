#!/usr/bin/env bash
#
# install.sh
# Installs packages (official + AUR), deploys bare git dotfiles
# and configures the sway session.
#
# Requirements: Arch Linux. yay will be built from AUR if not already installed.
#

set -euo pipefail

DOTFILES_REPO="https://github.com/wlroots/dotfiles-home"
DOTFILES_DIR="$HOME/.dotfiles"

OFFICIAL_PKGS=(
    git
    noto-fonts-emoji
    noto-fonts-cjk
    ttf-dejavu
    ttf-liberation
    bash-completion
    terminus-font
    base-devel
    neovim
    sway
    grim
    mako
    slurp
    swaybg
    waybar
    sway-contrib
    swayidle
    fuzzel
    swaylock
    xdg-desktop-portal-gtk
    xdg-desktop-portal-wlr
    xorg-xwayland
    nwg-look
    adw-gtk-theme
    xwayland-satellite
    brightnessctl
    sddm
    ttf-jetbrains-mono
    mate-polkit
    blueman
    ttf-jetbrains-mono-nerd
    woff2-font-awesome
    alacritty
    network-manager-applet
    otf-font-awesome
    swayosd
    mpv
    dolphin
    yt-dlp
    yt-dlp-ejs
    pavucontrol
    qbittorrent
    papirus-icon-theme
    easyeffects
    noto-fonts
    noto-fonts-extra
    awww
    sassc
    glycin-gtk4
    tauon-music-box
    obsidian
    zed
    pipewire
    pipewire-pulse
    pipewire-alsa
    pipewire-jack
    wireplumber
)

AUR_PKGS=(
    ttf-ms-fonts
    sway-audio-idle-inhibit-git
    swaysettings-git
    helium-browser-bin
    waypaper
    qt6ct-kde
)

log() {
    echo ">>> $1"
}

err() {
    echo "!!! $1" >&2
    exit 1
}

require_not_root() {
    if [ "$(id -u)" -eq 0 ]; then
        err "Do not run this script as root. Run it as a normal user with sudo."
    fi
}

require_arch() {
    if [ ! -f /etc/os-release ]; then
        err "/etc/os-release not found. Cannot verify this is Arch Linux."
    fi

    # shellcheck disable=SC1091
    . /etc/os-release

    local is_arch=0

    if [ "${ID:-}" = "arch" ]; then
        is_arch=1
    fi

    if [ "$is_arch" -eq 0 ] && [ -n "${ID_LIKE:-}" ]; then
        for like in $ID_LIKE; do
            if [ "$like" = "arch" ]; then
                is_arch=1
                break
            fi
        done
    fi

    if [ "$is_arch" -eq 0 ]; then
        err "This script only supports Arch Linux (or Arch-based distros). Detected ID=${ID:-unknown}, ID_LIKE=${ID_LIKE:-unknown}"
    fi

    log "Arch Linux detected (ID=${ID:-unknown}, ID_LIKE=${ID_LIKE:-none}). Proceeding."
}

install_official_pkgs() {
    log "Installing official packages via pacman..."
    sudo pacman -S --needed --noconfirm "${OFFICIAL_PKGS[@]}"
}

ensure_yay() {
    if command -v yay >/dev/null 2>&1; then
        log "yay is already installed, skipping build."
        return
    fi

    log "yay not found, building yay-bin manually from AUR..."
    local tmpdir
    tmpdir="$(mktemp -d)"
    git clone https://aur.archlinux.org/yay-bin.git "$tmpdir/yay-bin"
    (
        cd "$tmpdir/yay-bin"
        makepkg -si --noconfirm
    )
    rm -rf "$tmpdir"
}

install_aur_pkgs() {
    log "Installing AUR packages via yay..."
    yay -S --needed --noconfirm "${AUR_PKGS[@]}"
}

setup_dotfiles() {
    if [ -d "$DOTFILES_DIR" ]; then
        log "Directory $DOTFILES_DIR already exists, skipping clone."
    else
        log "Cloning bare dotfiles repository..."
        git clone --bare "$DOTFILES_REPO" "$DOTFILES_DIR"
    fi

    log "Backing up conflicting files (if any)..."
    local backup_dir="$HOME/.dotfiles-backup"
    mkdir -p "$backup_dir"

    local checkout_output
    if ! checkout_output=$(git --git-dir="$DOTFILES_DIR" --work-tree="$HOME" checkout 2>&1); then
        while read -r line; do
            # Removing spaces
            file="$(echo "$line" | xargs)"
            # checking if it in homedir
            if [ -n "$file" ] && [ -f "$HOME/$file" ]; then
                mkdir -p "$backup_dir/$(dirname "$file")"
                mv "$HOME/$file" "$backup_dir/$file"
                log "Moved conflicting file: $file -> $backup_dir/$file"
            fi
            done < <(echo "$checkout_output" | grep -E '^\s+\S' | grep -v 'error:')

            git --git-dir="$DOTFILES_DIR" --work-tree="$HOME" checkout
	    git --git-dir="$DOTFILES_DIR" --work-tree="$HOME" submodule update --init --recursive
    fi

    git --git-dir="$DOTFILES_DIR" --work-tree="$HOME" config --local status.showUntrackedFiles no

    log "Dotfiles deployed. Backups (if any) are in $backup_dir"
}

setup_symlink_and_session() {
    local sway_run_src="$HOME/.local/bin/sway-run"

    if [ ! -f "$sway_run_src" ]; then
        err "File $sway_run_src not found. Check if your dotfiles repository contains it."
    fi
    log "Making $sway_run_src executable..."
    chmod +x "$sway_run_src"

    log "Creating symlink /usr/local/bin/sway-run..."
    sudo ln -sf "$sway_run_src" /usr/local/bin/sway-run

    log "Creating /usr/share/wayland-sessions/sway-wrap.desktop..."
    sudo tee /usr/share/wayland-sessions/sway-wrap.desktop >/dev/null <<'EOF'
[Desktop Entry]
Name=Sway (With XWayland)
Comment=An i3-compatible Wayland compositor
Exec=sway-run
Type=Application
DesktopNames=sway;wlroots
EOF
}

enable_sddm() {
    if systemctl is-enabled sddm >/dev/null 2>&1; then
        log "sddm is already enabled."
    else
        log "Enabling sddm..."
        sudo systemctl enable sddm
    fi
}

enable_pipewire() {
    if systemctl is-enabled wireplumber >/dev/null 2>&1; then
        log "pipewire is already enabled."
    else
        log "Enabling pipewire..."
        systemctl enable --user wireplumber pipewire-pulse pipewire
    fi
}

main() {
    require_arch
    require_not_root
    install_official_pkgs
    ensure_yay
    install_aur_pkgs
    setup_dotfiles
    setup_symlink_and_session
    enable_sddm
    enable_pipewire
    log "Done. Reboot and select the 'Sway (With XWayland)' session in sddm."
}

main "$@"
