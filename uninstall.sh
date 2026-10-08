#!/usr/bin/env bash
# Reverts install.sh: restores the default lock screen wallpaper and removes everything.
set -euo pipefail
kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin org.kde.image
systemctl --user disable --now solat-lock.timer solat-lock.path solat-lock-notify.service || true
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}"/systemd/user/solat-lock{.service,.timer,.path,-notify.service}
systemctl --user daemon-reload
kpackagetool6 -t Plasma/Wallpaper -r solat.lockscreen || true
cargo uninstall solat-lock || true
