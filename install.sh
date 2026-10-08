#!/usr/bin/env bash
# Installs solat-lock for the current user from source (cargo + ~/.local).
# On Arch, prefer the package: cd packaging/arch && makepkg -si
set -euo pipefail
cd "$(dirname "$0")"

cargo install --path . --locked

if kpackagetool6 -t Plasma/Wallpaper -s solat.lockscreen >/dev/null 2>&1; then
    kpackagetool6 -t Plasma/Wallpaper -u plasma
else
    kpackagetool6 -t Plasma/Wallpaper -i plasma
fi

units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$units"
for unit in systemd/*; do
    sed "s|/usr/bin/solat-lock|$HOME/.cargo/bin/solat-lock|" "$unit" > "$units/$(basename "$unit")"
done
"$HOME/.cargo/bin/solat-lock" setup
systemctl --user restart solat-lock-notify.service
