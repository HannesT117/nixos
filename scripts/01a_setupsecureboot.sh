#!/usr/bin/env bash
set -euo pipefail

echo "=== Step 1: Generate Secure Boot signing keys ==="
if [ -f /var/lib/sbctl/keys/db/db.pem ]; then
  echo "Keys already exist, skipping creation."
else
  sudo sbctl create-keys
fi
echo ""

echo "=== Step 2: Build, sign, and verify ==="
sudo nixos-rebuild switch --flake /etc/nixos#gmktec --extra-experimental-features "flakes nix-command"
echo ""
echo "Verifying all EFI binaries are signed:"
sudo sbctl verify
echo ""

echo "=== Step 3: Reboot into UEFI Setup Mode ==="
echo "After reboot:"
echo "  1. Enter UEFI firmware settings"
echo "  2. Go to Secure Boot settings"
echo "  3. Delete Secure Boot keys. Seems like it has to be done individually on GMKtec? -> PK, key exchange keys, authorized signatures (enters Setup Mode)"
echo "  4. Enable Secure Boot"
echo "  5. Save and boot back into NixOS"
echo ""
read -p "Press Enter to reboot..."
sudo reboot

# --- Run the rest after rebooting back into NixOS ---
