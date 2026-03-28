#!/usr/bin/env bash
set -euo pipefail

# Run this script from a NixOS installer USB to set up the gmktec from scratch.
# It clones the repo, formats the disk, sets up passwords and Secure Boot keys,
# and installs NixOS.
#
# Usage (from the NixOS installer):
#   git clone https://github.com/HannesT117/homeserver /tmp/nixos
#   bash /tmp/nixos/scripts/00_install.sh
#
# The repo is cloned to /mnt/persist/etc/nixos during install.
# On the running system it is available at /etc/nixos (bind-mounted from /persist).
#
# After reboot into the new system, run scripts in order:
#   01a_secureboot_verify.sh  →  (UEFI: delete keys)  →  01b_secureboot_enroll.sh  →  (UEFI: enable SB)  →  02_setuptpm2.sh

NIX="nix --extra-experimental-features flakes --extra-experimental-features nix-command"
NIXPKGS="github:NixOS/nixpkgs/nixos-unstable"
REPO_URL="https://github.com/HannesT117/homeserver"
FLAKE_DIR="/mnt/persist/etc/nixos"

echo "=== gmktec NixOS Install ==="
echo ""

# Verify we are NOT running from the target disk
if mount | grep -q '/dev/mapper/cryptroot on / '; then
  echo "ERROR: You are booted from the disk you are trying to format."
  echo "Boot from a NixOS installer USB and run this script from there."
  exit 1
fi

# Clone or update the repo
if [ -d "$FLAKE_DIR/.git" ]; then
  echo "Updating existing repo at $FLAKE_DIR..."
  git -C "$FLAKE_DIR" pull
else
  echo "Cloning repo to $FLAKE_DIR..."
  git clone "$REPO_URL" "$FLAKE_DIR"
fi

echo ""
echo "WARNING: This will DESTROY all data on /dev/nvme0n1."
read -p "Type 'yes' to continue: " confirm
[[ "$confirm" == "yes" ]] || { echo "Aborted."; exit 1; }

echo ""
echo "=== Preparing disk ==="
sudo cryptsetup close cryptroot 2>/dev/null || true
sudo wipefs -af /dev/nvme0n1
sudo udevadm settle

echo ""
echo "=== Formatting disk and creating subvolumes ==="
echo "You will be prompted to set the LUKS passphrase."
echo ""
sudo $NIX run github:nix-community/disko -- \
  --mode destroy,format,mount \
  "$FLAKE_DIR/nix/hosts/gmktec/disko.nix"

echo ""
echo "=== Creating Secure Boot keys ==="
echo "Lanzaboote needs signing keys to install the bootloader."
sudo $NIX run "$NIXPKGS#sbctl" -- create-keys
sudo mkdir -p /mnt/persist/var/lib/sbctl
sudo cp -r /var/lib/sbctl/* /mnt/persist/var/lib/sbctl/
sudo mount --bind /mnt/persist/var/lib/sbctl /mnt/var/lib/sbctl

echo ""
echo "=== Installing NixOS ==="
sudo nixos-install --flake "$FLAKE_DIR#gmktec" --no-root-password
sudo umount /mnt/var/lib/sbctl

echo ""
echo "=== Setting root password ==="
echo "This is persisted in /etc/shadow via impermanence."
echo "Change later with: passwd (as root)"
# Copy the shadow file nixos-install created, set root's password, persist it
HASH=$(sudo $NIX run "$NIXPKGS#mkpasswd" -- -m yescrypt)
sudo sed -i "s|^root:[^:]*:|root:$HASH:|" /mnt/etc/shadow
sudo mkdir -p /mnt/persist/etc
sudo cp /mnt/etc/shadow /mnt/persist/etc/shadow

echo ""
echo "=== Done ==="
echo "Reboot into the new system, then run scripts in order:"
echo "  1. 01a_secureboot_verify.sh   (verifies signed binaries, reboots)"
echo "  2. (UEFI: delete all keys, save and boot)"
echo "  3. 01b_secureboot_enroll.sh   (enrolls keys into firmware, reboots)"
echo "  4. (UEFI: enable Secure Boot, save and boot)"
echo "  5. 02_setuptpm2.sh            (enrolls TPM2 for LUKS auto-unlock)"
echo ""
read -p "Press Enter to reboot..."
sudo reboot
