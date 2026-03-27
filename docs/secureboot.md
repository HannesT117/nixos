# Secure Boot + TPM2 LUKS on NixOS

## Why Bother

**Secure Boot + TPM2 LUKS** = disk auto-unlocks on every boot, but only if the entire boot chain (firmware → bootloader → kernel) is unmodified. No passphrase, no YubiKey touch — and a tampered system stays locked.

Secure Boot alone is weak. TPM2 LUKS alone is security theater (modified kernel boots and gets the key anyway). Together they're meaningful.

## How It Works

```
UEFI firmware
  └─ verifies BOOTX64.EFI (signed with your custom key)
       └─ systemd-boot loads a UKI
            └─ lanzaboote stub (signed) checks Secure Boot is active
                 └─ boots NixOS, TPM unseals LUKS key
```

**lanzaboote** creates signed Unified Kernel Images (UKIs) and replaces standard NixOS boot entries. **sbctl** manages signing keys and enrolls them into UEFI firmware.

## NixOS Configuration

```nix
imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

boot.loader.systemd-boot.enable = lib.mkForce false; # lanzaboote takes over
boot.lanzaboote = {
  enable = true;
  pkiBundle = "/var/lib/sbctl";
};

boot.initrd.systemd.enable = true;
boot.initrd.kernelModules = [ "tpm_crb" ];

boot.initrd.luks.devices."cryptroot".crypttabExtraOpts = [
  "tpm2-device=auto"   # TPM2 first
  "fido2-device=auto"  # YubiKey fallback
  "token-timeout=60"
];
```

`lib.mkForce false` is needed because lanzaboote's module internally sets `systemd-boot.enable = true`.

## Setup Procedure

Order is strict — deviating bricks the system.

### Step 1 — Generate keys (once)
```bash
sudo sbctl create-keys
```

### Step 2 — Build and sign
```bash
sudo nixos-rebuild switch --flake /etc/nixos#gmktec
sudo sbctl verify   # every line must show ✓
```

### Step 3 — Enter UEFI Setup Mode
Reboot → UEFI → Secure Boot → **Delete all keys** (enters Setup Mode) → **enable Secure Boot** → save → boot into NixOS.

```bash
sudo sbctl status   # must show: Setup Mode: ✓ Enabled
```

### Step 4 — Enroll keys
```bash
sudo sbctl enroll-keys --microsoft   # --microsoft keeps GPU/NIC firmware working
sudo sbctl status                    # must show: Setup Mode: ✗ Disabled
```

### Step 5 — Reboot
```bash
sudo sbctl status   # must show: Secure Boot: ✓ Enabled
```

### Step 6 — Enroll TPM2 for LUKS auto-unlock
```bash
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/nvme0n1p2
sudo nixos-rebuild switch --flake /etc/nixos#gmktec
```

PCR7 binds the TPM key to Secure Boot state — any Secure Boot change requires re-enrollment.

### Why this order matters

| Rule | Reason |
|------|--------|
| Sign before enrolling | Unsigned files won't boot once Secure Boot enforces |
| `sbctl verify` before enrolling | Catches unsigned binaries before locking firmware |
| Setup Mode before enrolling | `sbctl enroll-keys` only works with no PK enrolled |
| Secure Boot enabled before TPM2 | TPM2 seals against current PCR7 — must reflect final state |
| TPM2 enrollment last | Any Secure Boot change after this invalidates the token |

---

## Recovery: Chroot from Ubuntu Live USB

### Mount the NixOS disk
```bash
sudo -i
cryptsetup open /dev/nvme0n1p2 cryptroot   # enter passphrase

mkdir -p /mnt
mount -o subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/nix
mount -o subvol=@nix /dev/mapper/cryptroot /mnt/nix
mount /dev/nvme0n1p1 /mnt/boot
mount -t efivarfs efivarfs /sys/firmware/efi/efivars   # needed for sbctl
```

### Enter chroot
```bash
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
mount --bind /dev /mnt/dev
mount -t devpts devpts /mnt/dev/pts   # must be -t devpts, not --bind
cp /etc/resolv.conf /mnt/etc/resolv.conf

chroot /mnt /nix/var/nix/profiles/system/sw/bin/bash
export PATH=/nix/var/nix/profiles/system/sw/bin:$PATH
```

### Rebuild
```bash
nixos-rebuild boot --flake /etc/nixos#gmktec --option sandbox false
```

`--option sandbox false` is required in chroot (missing pseudo-terminal support).

### Common pitfalls
- Edit `boot.loader.systemd-boot.enable` **in place** — adding a second line causes "attribute already defined"
- `devpts` must use `-t devpts`, not `--bind` — otherwise nixos-rebuild fails with "opening pseudoterminal master: no such device"
- Old lanzaboote UKIs in `/boot/EFI/Linux/` are booted by systemd-boot instead of new generations — delete them manually after rebuilds

---

## What Went Wrong

| Mistake | Effect |
|---------|--------|
| Enrolled keys before signing EFI files | Nothing booted — signed files and enrolled keys didn't match |
| `efivarfs` not mounted during enrollment | Enrollment silently wrote nothing |
| "Clear all Secure Boot keys" in UEFI UI | Replaced custom PK with AMI test PK, didn't enter Setup Mode |
| CMOS reset to clear Secure Boot | Secure Boot variables live in SPI flash, not CMOS — no effect |
| Re-enabled lanzaboote before fixing TPM2 | Two simultaneous failures: lanzaboote panic + TPM2 unlock failure |
| Enrolled TPM2 before finalising Secure Boot | PCR7 changed when Secure Boot enabled — TPM refused to unseal |
| Old UKIs left in `/boot/EFI/Linux/` | systemd-boot kept booting broken generations instead of new one |

---

## Removing Bricked Generations

```bash
sudo nix-env -p /nix/var/nix/profiles/system --list-generations
sudo nix-env -p /nix/var/nix/profiles/system --delete-generations 16 17 18
sudo nix-collect-garbage
sudo nixos-rebuild boot --flake /etc/nixos#gmktec   # removes stale UKIs from /boot/EFI/Linux/
```
