# Lanzaboote + TPM2 LUKS Unlock

**Date:** 2026-03-27
**Status:** Approved

## Goal

Replace the current YubiKey-at-every-boot FIDO2 LUKS unlock with automatic TPM2-based unlocking secured by Secure Boot (PCR 7), while keeping the YubiKey enrolled as a fallback.

## Context

- Machine: GMKTec NucBox G3 Plus (x86_64, Intel, NVMe, TPM2 present)
- Current boot: UEFI → systemd-boot → initrd → FIDO2 prompt → LUKS → btrfs → NixOS
- LUKS device: `/dev/nvme0n1p2`, btrfs subvolumes `@`, `@home`, `@nix`, `@snapshots`
- `boot.initrd.systemd.enable = true` already in place
- Threat model: home use — unattended reboot convenience outweighs theoretical TPM extraction risk

## Boot Chain After Change

```
UEFI (Secure Boot) → lanzaboote → signed kernel + initrd → TPM2 auto-unseals LUKS → btrfs → NixOS
```

Lanzaboote signs the kernel and initrd on every `nixos-rebuild switch`. The UEFI firmware verifies those signatures. PCR 7 (Secure Boot policy state — enrolled keys, Secure Boot enablement, and key databases) is typically stable across NixOS kernel and initrd upgrades. However it can change if a UEFI firmware update modifies the Secure Boot revocation database (DBX) — in that case, re-run the `systemd-cryptenroll` command with the YubiKey inserted. The YubiKey (FIDO2) remains enrolled as fallback throughout.

## NixOS Config Changes

### `flake.nix`
- Add `lanzaboote` as a flake input, pinned to a release tag
- Follow `nixpkgs` for the lanzaboote input
- Pass `inputs` through `specialArgs` (already done)

### `hosts/gmktec/default.nix`
- Add `lib` to the module argument set (needed for `lib.mkForce`)
- Import `inputs.lanzaboote.nixosModules.lanzaboote`
- Disable systemd-boot: `boot.loader.systemd-boot.enable = lib.mkForce false`
- Enable lanzaboote:
  ```nix
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/etc/secureboot";
  };
  ```
- Add `sbctl` to system packages
- Add `tpm2-device=auto` to LUKS crypttab options alongside existing `fido2-device=auto`
- Add `tpm_crb` to `boot.initrd.kernelModules` to ensure the TPM driver is available in the initrd (Intel systems typically use `tpm_crb`; verify with `ls /sys/class/tpm/` if uncertain)
- Retain `boot.loader.efi.canTouchEfiVariables = true` (harmless, not needed by lanzaboote itself)

No changes to `hardware-configuration.nix` or any service file.

## One-Time Manual Steps

Must be performed in order. YubiKey fallback is intact at every step.

**Prerequisite:** Confirm a LUKS passphrase is enrolled (`sudo cryptsetup luksDump /dev/nvme0n1p2` — look for a passphrase keyslot). If only FIDO2 is enrolled, add a passphrase now: `sudo cryptsetup luksAddKey /dev/nvme0n1p2`. This is essential recovery insurance.

1. Add lanzaboote to `flake.nix` and run `nix flake update` (or pin to a specific tag)
2. `sudo sbctl create-keys` — generate Secure Boot key pair under `/etc/secureboot` **before deploying**
3. `nixos-rebuild switch` — deploys lanzaboote; it finds the keys and signs the kernel/initrd automatically
4. `sudo sbctl verify` — confirm all boot files are signed (no unsigned entries)
5. Boot into UEFI firmware → enter **Setup Mode** (clears factory keys, allows enrollment)
6. Boot back into NixOS → `sudo sbctl enroll-keys --microsoft` (enrolls your keys + Microsoft UEFI CA for firmware driver compatibility)
7. `sudo sbctl status` — verify enrollment looks correct
8. Boot into UEFI firmware → **enable Secure Boot** (Setup Mode is already exited after key enrollment in step 6)
9. Boot into NixOS — confirm system works with Secure Boot active
10. Back up the LUKS header: `sudo cryptsetup luksHeaderBackup /dev/nvme0n1p2 --header-backup-file ~/luks-header-backup.img` — store this somewhere safe
11. With YubiKey inserted: `sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p2`
12. Reboot — confirm auto-unlock (no YubiKey prompt)
13. `sudo systemd-cryptenroll --list-tokens /dev/nvme0n1p2` — confirm YubiKey token still present

## Risks and Recovery

| Risk | Mitigation |
|------|-----------|
| Secure Boot breaks boot | Disable Secure Boot in UEFI temporarily; YubiKey fallback works regardless |
| TPM stops unsealing after firmware update | PCR 7 can change if UEFI updates its DBX; re-run `systemd-cryptenroll` with YubiKey inserted |
| `/etc/secureboot` lost | Must re-run `sbctl create-keys` + `sbctl enroll-keys` and re-enable Secure Boot; note this path as a future impermanence persistence entry |
| YubiKey lost, no passphrase enrolled | Unrecoverable — ensure a passphrase keyslot is enrolled (see prerequisite step) and keep the LUKS header backup |
| Wrong UEFI Setup Mode procedure | UEFI firmware UIs vary; keep YubiKey available throughout |

## Future Work

- **Impermanence**: ephemeral root via btrfs blank-snapshot rollback on boot. Will need to explicitly persist `/etc/secureboot`, `/var/lib/syncthing`, `/var/lib/paperless`, `/var/lib/tailscale`, SSH host keys, machine-id, NetworkManager connections.
