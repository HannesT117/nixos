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
sudo nix run github:nix-community/disko --extra-experimental-features "flakes nix-command" -- \
  --mode destroy,format,mount \
  "$FLAKE_DIR/nix/hosts/gmktec/disko.nix"

echo ""
echo "=== Setting root password ==="
echo "This password is used for 'su -' from the unprivileged nonroot account."
echo "It is stored as a hash on /persist and survives impermanence wipes."
sudo mkdir -p /mnt/persist/secrets
HASH=$(nix run github:NixOS/nixpkgs/nixos-unstable#mkpasswd --extra-experimental-features "flakes nix-command" -- -m yescrypt)
echo "$HASH" | sudo tee /mnt/persist/secrets/root-password-hash > /dev/null
sudo chmod 600 /mnt/persist/secrets/root-password-hash

echo ""
echo "=== Creating temporary Secure Boot keys ==="
echo "Lanzaboote needs signing keys to install. These are placeholders —"
echo "01a_setupsecureboot.sh will regenerate real keys after first boot."
sudo nix run nixpkgs#sbctl --extra-experimental-features "flakes nix-command" -- create-keys
# Bind-mount keys into target so lanzaboote finds them inside the nixos-install chroot
sudo mkdir -p /mnt/var/lib/sbctl
sudo mount --bind /var/lib/sbctl /mnt/var/lib/sbctl

echo ""
echo "=== Installing NixOS ==="
sudo nixos-install --flake "$FLAKE_DIR#gmktec" --no-root-password
sudo umount /mnt/var/lib/sbctl

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
