#!/usr/bin/env bash
set -euo pipefail

# Run on the installed system after 00_install.sh.
# Verifies all EFI binaries are signed, then reboots for UEFI Setup Mode.

echo "=== Secure Boot: Verify Signed Binaries ==="
echo ""
sudo sbctl status
echo ""
sudo sbctl verify
echo ""
echo "All good. Now reboot and put the firmware into Setup Mode."
echo ""
echo "  ┌─────────────────────────────────────────────────┐"
echo "  │  MANUAL STEPS (do these after reboot):          │"
echo "  │                                                 │"
echo "  │  1. Enter UEFI firmware settings                │"
echo "  │  2. Go to Secure Boot settings                  │"
echo "  │  3. Delete ALL Secure Boot keys (Setup Mode)    │"
echo "  │  4. Save and boot back into NixOS               │"
echo "  │                                                 │"
echo "  │  Then run 01b_secureboot_enroll.sh              │"
echo "  └─────────────────────────────────────────────────┘"
echo ""
read -p "Press Enter to reboot into UEFI..."
sudo reboot
