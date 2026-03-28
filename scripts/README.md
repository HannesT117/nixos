# Scripts

Setup scripts for the gmktec NixOS server. Run them in numbered order when needed.

## When do I need to run these?

| Situation | Scripts to run |
|-----------|---------------|
| Fresh install or reinstall | `00` → `01a` → *(UEFI: delete keys)* → `01b` → *(UEFI: enable SB)* → `02` |
| Secure Boot keys lost or recreated | `00` (re-creates keys) → `01a` → *(UEFI: delete keys)* → `01b` → *(UEFI: enable SB)* → `02` |
| Secure Boot config changed (PCR7 affected) | `02` only |
| Normal config change (`nixos-rebuild switch`) | None |

## Scripts

### `00_install.sh` — Fresh install

Run from a **NixOS installer USB** — not from the installed system.

Clones the repo, formats `/dev/nvme0n1` via disko, prompts for LUKS passphrase and root password, creates Secure Boot signing keys, and installs NixOS.

```bash
git clone https://github.com/HannesT117/homeserver /tmp/nixos
bash /tmp/nixos/scripts/00_install.sh
```

> **Must boot from installer USB.** You cannot format the disk you are currently running from.

---

### `01a_secureboot_verify.sh` — Verify signed binaries

Run on the **installed system** after first boot.

Verifies all EFI binaries are signed, then reboots for UEFI Setup Mode.

```bash
bash scripts/01a_secureboot_verify.sh
```

**After reboot**, enter UEFI firmware settings:
1. Go to **Secure Boot** settings
2. **Delete all keys** — puts the firmware into Setup Mode
3. Save and boot back into NixOS

---

### `01b_secureboot_enroll.sh` — Enroll keys into firmware

Run after returning from UEFI with Setup Mode active.

Enrolls custom keys (`--microsoft` keeps GPU/NIC firmware working) and reboots.

```bash
bash scripts/01b_secureboot_enroll.sh
```

**After reboot**, enter UEFI firmware settings:
1. Go to **Secure Boot** settings
2. **Enable Secure Boot** (now possible since PK is enrolled)
3. Save and boot back into NixOS

---

### `02_setuptpm2.sh` — TPM2 LUKS auto-unlock

Run after Secure Boot is confirmed active (`sudo sbctl status` shows `Secure Boot: ✓ Enabled`).

Enrolls a TPM2 token so the disk unlocks automatically at boot. The LUKS passphrase remains as a fallback.

Must run **after** Secure Boot is fully configured: the TPM2 token is sealed against the current Secure Boot state (PCR7). If Secure Boot configuration changes later, re-run this script.

```bash
bash scripts/02_setuptpm2.sh
```
