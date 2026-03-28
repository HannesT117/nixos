#!/usr/bin/env bash
set -euo pipefail

# Run this script from a NixOS installer USB to set up the gmktec from scratch.
# It formats the disk, creates all partitions and btrfs subvolumes via disko,
# and installs NixOS.
#
# After this script completes and you reboot into the new system, run:
#   01a_setupsecureboot.sh  →  (UEFI interaction)  →  01b_enrollkeys.sh  →  02_setuptpm2.sh

FLAKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== gmktec NixOS Install ==="
echo "Flake: $FLAKE_DIR"
echo ""

# Verify we are NOT running from the target disk
if mount | grep -q '/dev/mapper/cryptroot on / '; then
  echo "ERROR: You are booted from the disk you are trying to format."
  echo "Boot from a NixOS installer USB and run this script from there."
  exit 1
fi

echo "WARNING: This will DESTROY all data on /dev/nvme0n1."
read -p "Type 'yes' to continue: " confirm
[[ "$confirm" == "yes" ]] || { echo "Aborted."; exit 1; }

echo ""
echo "=== Preparing disk ==="
# Close any existing LUKS mapping on this device
sudo cryptsetup close cryptroot 2>/dev/null || true
sudo wipefs -af /dev/nvme0n1
sudo udevadm settle

echo "=== Formatting disk and creating subvolumes ==="
echo "You will be prompted to set the LUKS passphrase."
echo ""
sudo nix run github:nix-community/disko -- \
  --mode destroy,format,mount \
  "$FLAKE_DIR/nix/hosts/gmktec/disko.nix"

echo ""
echo "=== Installing NixOS ==="
sudo nixos-install --flake "$FLAKE_DIR#gmktec" --no-root-password

echo ""
echo "=== Done ==="
echo "Reboot into the new system, then run scripts in order:"
echo "  1. 01a_setupsecureboot.sh"
echo "  2. (UEFI: delete all keys, enable Secure Boot, reboot)"
echo "  3. 01b_enrollkeys.sh"
echo "  4. (reboot)"
echo "  5. 02_setuptpm2.sh"
echo ""
read -p "Press Enter to reboot..."
sudo reboot
