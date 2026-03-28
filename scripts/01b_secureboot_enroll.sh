#!/usr/bin/env bash
set -euo pipefail

# Run after returning from UEFI with Setup Mode active.
# Enrolls custom Secure Boot keys into firmware and reboots.

echo "=== Secure Boot: Enroll Keys ==="
echo ""
sudo sbctl status
echo ""

if ! sudo sbctl status 2>&1 | grep -qi "setup mode.*enabled"; then
  echo "ERROR: Setup Mode is not active."
  echo "Reboot into UEFI, delete all Secure Boot keys, then try again."
  exit 1
fi

read -p "Setup Mode confirmed. Press Enter to enroll keys..."
sudo sbctl enroll-keys --microsoft
echo ""
echo "=== Verifying enrollment ==="
sudo sbctl status
echo ""
echo "Check above: Vendor Keys should show 'microsoft' (was 'none' before enrollment)."
echo "Setup Mode will stay Enabled until Secure Boot is turned on in UEFI."
echo ""
read -p "Does the output look correct? (yes/no): " confirm
[[ "$confirm" == "yes" ]] || { echo "Aborting. Debug with: sudo sbctl status"; exit 1; }
echo ""
echo "Keys enrolled. Now enable Secure Boot in UEFI."
echo ""
echo "  ┌─────────────────────────────────────────────────┐"
echo "  │  MANUAL STEPS (do these after reboot):          │"
echo "  │                                                 │"
echo "  │  1. Enter UEFI firmware settings                │"
echo "  │  2. Go to Secure Boot settings                  │"
echo "  │  3. Enable Secure Boot                          │"
echo "  │  4. Save and boot back into NixOS               │"
echo "  │                                                 │"
echo "  │  Then run 02_setuptpm2.sh                       │"
echo "  └─────────────────────────────────────────────────┘"
echo ""
read -p "Press Enter to reboot into UEFI..."
sudo reboot
