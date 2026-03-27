# Lanzaboote + TPM2 LUKS Unlock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace YubiKey-at-every-boot FIDO2 LUKS unlock with automatic TPM2 unlocking secured by Secure Boot (PCR 7), keeping YubiKey as fallback.

**Architecture:** Two NixOS config files are edited on the Mac, committed, and pulled onto the server. After `nixos-rebuild switch`, a sequence of manual server-side steps enrolls Secure Boot keys and the TPM2 LUKS token. The code changes and the manual steps are deliberately separated — the code can be reviewed in a dry build before any server interaction.

**Tech Stack:** NixOS flakes, lanzaboote v1.0.0, sbctl, systemd-cryptenroll, btrfs, LUKS2

---

## File Map

| Action | File | Change |
|--------|------|--------|
| Modify | `flake.nix` | Add lanzaboote flake input |
| Modify | `nix/hosts/gmktec/default.nix` | Add `lib` arg, import lanzaboote module, disable systemd-boot, enable lanzaboote, add sbctl package, add TPM kernel module, add `tpm2-device=auto` to crypttab opts |

No other files change.

---

## Task 1: Add lanzaboote input to flake.nix

**Files:**
- Modify: `flake.nix`

*Work on the Mac. The server is not touched until Task 3.*

- [ ] **Step 1.1: Add lanzaboote to `inputs`**

  In `flake.nix`, add after the `nixos-hardware` input:

  ```nix
  lanzaboote = {
    url = "github:nix-community/lanzaboote/v1.0.0";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  ```

- [ ] **Step 1.2: Expose lanzaboote in `outputs`**

  The `outputs` function currently destructures `{ self, nixpkgs, nixos-hardware, ... } @ inputs`. The `... @ inputs` already captures all inputs — `lanzaboote` is available via `inputs.lanzaboote` in `specialArgs` which is already passed. **No change needed to the outputs function signature.**

- [ ] **Step 1.3: Validate the flake parses**

  Run on the Mac (doesn't need to build — just checks syntax and inputs):
  ```bash
  nix flake metadata
  ```
  Expected: no errors, lanzaboote appears in the inputs list.

- [ ] **Step 1.4: Commit**

  ```bash
  git add flake.nix flake.lock
  git commit -m "feat: add lanzaboote flake input (v1.0.0)"
  ```

---

## Task 2: Configure lanzaboote in default.nix

**Files:**
- Modify: `nix/hosts/gmktec/default.nix`

- [ ] **Step 2.1: Add `lib` to the module argument set**

  Change the first line from:
  ```nix
  { inputs, pkgs, ... }:
  ```
  to:
  ```nix
  { inputs, pkgs, lib, ... }:
  ```

- [ ] **Step 2.2: Import the lanzaboote NixOS module**

  In the `imports` list, add as the first entry (before nixos-hardware):
  ```nix
  inputs.lanzaboote.nixosModules.lanzaboote
  ```

- [ ] **Step 2.3: Replace systemd-boot with lanzaboote**

  Replace the existing boot loader block:
  ```nix
  # Boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.editor = false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;
  ```
  with:
  ```nix
  # Boot
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;
  boot.initrd.kernelModules = [ "tpm_crb" ];

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/etc/secureboot";
  };
  ```

  Notes:
  - `lib.mkForce false` is required because lanzaboote sets `systemd-boot.enable = true` internally; `mkForce` wins the priority contest.
  - `systemd-boot.editor = false` is dropped — it's meaningless when systemd-boot is disabled.
  - `tpm_crb` loads the TPM driver in the initrd (standard for Intel systems). Verify with `ls /sys/class/tpm/` after boot if uncertain.
  - `canTouchEfiVariables = true` is retained; lanzaboote does not need it but it's harmless.

- [ ] **Step 2.4: Add `tpm2-device=auto` to LUKS crypttab options**

  Change:
  ```nix
  boot.initrd.luks.devices."cryptroot".crypttabExtraOpts = [
    "fido2-device=auto"
    "token-timeout=60"
  ];
  ```
  to:
  ```nix
  boot.initrd.luks.devices."cryptroot".crypttabExtraOpts = [
    "tpm2-device=auto"
    "fido2-device=auto"
    "token-timeout=60"
  ];
  ```

  `tpm2-device=auto` is tried first; if it fails (e.g. PCR mismatch), `fido2-device=auto` catches it with the YubiKey.

- [ ] **Step 2.5: Add sbctl to system packages**

  Add an `environment.systemPackages` block (or extend the existing one):
  ```nix
  environment.systemPackages = with pkgs; [
    sbctl
  ];
  ```

- [ ] **Step 2.6: Dry-build to validate the config (on Mac)**

  ```bash
  nix build .#nixosConfigurations.gmktec.config.system.build.toplevel --dry-run
  ```
  Expected: evaluation succeeds, no `lib` not found or module errors. (It will not build the kernel — `--dry-run` only evaluates.)

- [ ] **Step 2.7: Commit**

  ```bash
  git add nix/hosts/gmktec/default.nix
  git commit -m "feat: enable lanzaboote, add TPM2 LUKS unlock config"
  ```

---

## Task 3: Server-side prerequisite check

*SSH into server. YubiKey must be available throughout all server tasks.*

- [ ] **Step 3.1: Confirm a LUKS passphrase keyslot exists**

  ```bash
  sudo cryptsetup luksDump /dev/nvme0n1p2 | grep -A2 "Keyslot"
  ```
  Look for a keyslot of type `luks2` with state `active` that is a **passphrase** (not FIDO2/token). If only FIDO2 is enrolled, add a passphrase now before continuing:
  ```bash
  sudo cryptsetup luksAddKey /dev/nvme0n1p2
  ```
  **This is a hard prerequisite. If the YubiKey is ever lost and no passphrase exists, the disk is unrecoverable.**

---

## Task 4: Create Secure Boot keys on the server

*SSH into server. Before pulling the new config.*

- [ ] **Step 4.1: Create the Secure Boot PKI bundle**

  ```bash
  sudo sbctl create-keys
  ```
  Expected: Creates keys under `/etc/secureboot/`. Output should include `Created Platform Key (PK)`, `Key Exchange Key (KEK)`, `Signature Database (db)`.

  **This must happen before `nixos-rebuild switch`. Lanzaboote needs the keys to sign the kernel/initrd on first build.**

---

## Task 5: Deploy the config

- [ ] **Step 5.1: Pull and switch**

  ```bash
  cd /etc/nixos && sudo git pull
  sudo nixos-rebuild switch --flake /etc/nixos#gmktec
  ```
  Expected: build succeeds, lanzaboote signs kernel and initrd. May see output like `Lanzaboote: signed /boot/EFI/Linux/...`.

- [ ] **Step 5.2: Verify all boot files are signed**

  ```bash
  sudo sbctl verify
  ```
  Expected: all listed files show `✓` (signed). If any show `✗`, lanzaboote did not sign them — investigate before proceeding.

---

## Task 6: Enroll Secure Boot keys in firmware

*These steps involve rebooting into the UEFI UI and back.*

- [ ] **Step 6.1: Boot into UEFI → enter Setup Mode**

  Reboot and enter the UEFI settings (typically `Delete` or `F2` during POST on GMKTec). Find the Secure Boot section and select **"Reset to Setup Mode"** or equivalent. This clears the factory Microsoft keys, allowing custom key enrollment.

  Do NOT enable Secure Boot yet — just enter Setup Mode and save/exit.

- [ ] **Step 6.2: Boot back into NixOS and enroll keys**

  ```bash
  sudo sbctl enroll-keys --microsoft
  ```
  `--microsoft` adds the Microsoft UEFI CA alongside your keys. This is important for firmware drivers (NVMe, network card) that are Microsoft-signed.

  Expected: `Enrolled keys to the EFI variable database`.

  Setup Mode is now exited automatically — the firmware transitioned to User Mode when keys were enrolled.

- [ ] **Step 6.3: Verify enrollment**

  ```bash
  sudo sbctl status
  ```
  Expected:
  ```
  Installed:   ✓ sbctl is installed
  Owner GUID:  <your GUID>
  Setup Mode:  ✗ Disabled
  Secure Boot: ✗ Disabled   ← still off, enabled in next step
  Vendor Keys: microsoft
  ```

- [ ] **Step 6.4: Boot into UEFI → enable Secure Boot**

  Reboot into UEFI settings. Find the Secure Boot section and **enable Secure Boot**. Save and exit.

- [ ] **Step 6.5: Verify Secure Boot is active**

  After booting into NixOS:
  ```bash
  sudo sbctl status
  ```
  Expected:
  ```
  Secure Boot: ✓ Enabled
  ```
  If the system doesn't boot, disable Secure Boot in UEFI — the YubiKey fallback will unlock LUKS regardless.

---

## Task 7: Enroll TPM2 LUKS token

- [ ] **Step 7.1: Back up the LUKS header**

  ```bash
  sudo cryptsetup luksHeaderBackup /dev/nvme0n1p2 \
    --header-backup-file ~/luks-header-backup.img
  ```
  Store this file somewhere off the machine (e.g. copy to Mac via `scp`). It's the only way to recover if the LUKS header is corrupted.

- [ ] **Step 7.2: Enroll the TPM2 token (with YubiKey inserted)**

  ```bash
  sudo systemd-cryptenroll \
    --tpm2-device=auto \
    --tpm2-pcrs=7 \
    /dev/nvme0n1p2
  ```
  You will be prompted for an existing credential (passphrase or YubiKey touch). PCR 7 seals the token to the current Secure Boot policy state.

  Expected: `New TPM2 token enrolled as key slot N.`

- [ ] **Step 7.3: Confirm both tokens are present**

  ```bash
  sudo cryptsetup luksDump /dev/nvme0n1p2
  ```
  Expected: in the `Tokens` section, both a `fido2` entry and a `systemd-tpm2` entry are listed.

---

## Task 8: Final verification

- [ ] **Step 8.1: Reboot without YubiKey**

  Remove the YubiKey and reboot. The disk should unlock automatically via TPM2 with no prompt.

- [ ] **Step 8.2: Confirm auto-unlock succeeded**

  ```bash
  sudo cryptsetup luksDump /dev/nvme0n1p2
  ```
  In the `Tokens` section, both `fido2` and `systemd-tpm2` entries should still be present — TPM2 unlock does not remove the FIDO2 token.

- [ ] **Step 8.3: Verify Secure Boot is still active**

  ```bash
  sudo sbctl status
  ```
  Expected: `Secure Boot: ✓ Enabled`

- [ ] **Step 8.4: Test YubiKey fallback (optional but recommended)**

  Boot with YubiKey inserted, then at a NixOS prompt:
  ```bash
  sudo systemctl restart systemd-cryptsetup@cryptroot.service
  ```
  Or simply confirm a cold boot with YubiKey also works (touches YubiKey during boot).

---

## Recovery Reference

| Problem | Recovery |
|---------|---------|
| System won't boot after Task 6 | Disable Secure Boot in UEFI; YubiKey fallback unlocks LUKS |
| TPM unsealing fails after firmware update | Boot with YubiKey → re-run Task 7 step 7.2 |
| `/etc/secureboot` lost | `sudo sbctl create-keys` → `sudo sbctl enroll-keys --microsoft` → re-enable Secure Boot in UEFI |
| YubiKey lost, passphrase enrolled | Use passphrase at LUKS prompt |
| YubiKey lost, no passphrase | Restore from LUKS header backup + passphrase if known; otherwise unrecoverable |
