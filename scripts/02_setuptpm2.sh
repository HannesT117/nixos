#!/usr/bin/env bash
set -euo pipefail

echo "=== Verifying Secure Boot is active ==="
sudo sbctl status
echo ""
echo "Secure Boot MUST be enabled before enrolling TPM2 (PCR7 must reflect final Secure Boot state)."
read -p "Confirm Secure Boot is Enabled above, then press Enter..."

# Device path for the LUKS partition on the gmktec NVMe
LUKS_DEVICE="/dev/nvme0n1p2"

echo "=== Enrolling TPM2 token for LUKS auto-unlock ==="
echo "Device: $LUKS_DEVICE"
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 "$LUKS_DEVICE"
echo ""

echo "=== Rebuilding to activate TPM2 config ==="
sudo nixos-rebuild switch --flake /etc/nixos#gmktec  --extra-experimental-features "flakes nix-command"
echo ""

echo "=== Done ==="
echo "Reboot to verify LUKS auto-unlocks without passphrase or YubiKey."
echo "If TPM2 unlock fails, the passphrase/FIDO2 fallback will prompt."
read -p "Press Enter to reboot..."
sudo reboot
