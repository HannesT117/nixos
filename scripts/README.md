# Scripts

Setup scripts for the gmktec NixOS server. Run them in numbered order when needed.

## When do I need to run these?

| Situation | Scripts to run |
|-----------|---------------|
| Fresh install or reinstall | `00` → `01a` → *(UEFI)* → `01b` → `02` |
| Secure Boot keys lost or recreated | `01a` → *(UEFI)* → `01b` → `02` |
| Secure Boot config changed (PCR7 affected) | `02` only |
| Normal config change (`nixos-rebuild switch`) | None |

## Scripts

### `00_install.sh` — Fresh install

Run from a **NixOS installer USB** — not from the installed system. The script checks this and exits with an error if you are booted from the target disk.

Formats `/dev/nvme0n1`, creates all partitions and btrfs subvolumes via disko, and installs NixOS. You will be prompted for a LUKS passphrase — this is the fallback if TPM2 unlock ever fails.

```bash
bash scripts/00_install.sh
```

> **Must boot from installer USB.** You cannot format the disk you are currently running from. If you see `Device or resource busy` or `cryptroot is still in use`, you are on the wrong system.

---

### `01a_setupsecureboot.sh` — Generate and sign

Run on the **installed system** (after reboot from installer).

1. Generates Secure Boot signing keys via `sbctl`
2. Builds and signs all EFI binaries
3. Reboots — you then enter UEFI firmware to enter Setup Mode

```bash
bash scripts/01a_setupsecureboot.sh
```

**After reboot**, enter UEFI firmware settings:
1. Go to **Secure Boot** settings
2. **Delete all keys** — this puts the firmware into Setup Mode
3. **Enable Secure Boot**
4. Save and reboot back into NixOS

---

### `01b_enrollkeys.sh` — Enroll keys into firmware

Run after returning from UEFI with Setup Mode active.

1. Verifies Setup Mode is enabled
2. Enrolls your custom keys into the firmware (`--microsoft` keeps GPU/NIC firmware working)
3. Reboots to activate Secure Boot enforcement

```bash
bash scripts/01b_enrollkeys.sh
```

---

### `02_setuptpm2.sh` — TPM2 LUKS auto-unlock

Run after Secure Boot is confirmed active (`sudo sbctl status` shows `Secure Boot: ✓ Enabled`).

Enrolls a TPM2 token so the disk unlocks automatically at boot — no passphrase or YubiKey needed. The LUKS passphrase remains as a fallback.

Must run **after** Secure Boot is fully configured: the TPM2 token is sealed against the current Secure Boot state (PCR7). If Secure Boot configuration changes later, re-run this script.

```bash
bash scripts/02_setuptpm2.sh
```
