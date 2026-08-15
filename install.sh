#!/usr/bin/env bash
# Installs dellmon into ~/.local/bin (symlink) and builds the macOS helper if needed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
case "$(uname -s)" in
  Darwin)
    swiftc -O -o "$HERE/macos/ddcvcp" "$HERE/macos/ddcvcp.swift" -framework IOKit -framework Foundation
    ;;
  Linux)
    command -v ddcutil >/dev/null || { echo "install ddcutil first (sudo apt install ddcutil)"; exit 1; }
    sudo modprobe i2c-dev
    grep -q '^i2c-dev' /etc/modules-load.d/i2c-dev.conf 2>/dev/null || echo i2c-dev | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
    getent group i2c >/dev/null && sudo usermod -aG i2c "$USER" || true
    ;;
esac
mkdir -p ~/.local/bin
ln -sf "$HERE/dellmon" ~/.local/bin/dellmon
echo "installed: ~/.local/bin/dellmon  (make sure ~/.local/bin is on PATH)"
"$HERE/dellmon" status || true
