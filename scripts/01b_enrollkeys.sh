#!/usr/bin/env bash
set -euo pipefail

echo "=== Verifying Setup Mode is active ==="
sudo sbctl status
echo ""
read -p "Confirm Setup Mode is Enabled above, then press Enter..."

echo "=== Enrolling keys into firmware ==="
sudo sbctl enroll-keys --microsoft
echo ""

echo "=== Verifying enrollment ==="
sudo sbctl status
echo ""

echo "=== Reboot to enforce Secure Boot ==="
read -p "Press Enter to reboot..."
sudo reboot

# --- After reboot, verify with: sudo sbctl status (should show Secure Boot: ✓ Enabled) ---
