# Impermanence for gmktec NixOS Server

## Context

The gmktec server runs NixOS with LUKS encryption, btrfs subvolumes, Secure Boot (lanzaboote), and TPM2 auto-unlock. Impermanence wipes `/` on every boot and forces all mutable state to be explicitly declared. Combined with the existing Secure Boot + TPM2 chain, every boot starts from a verified, known-clean state.

## Why Impermanence Makes Sense Here

1. **Completes the trust chain** — Secure Boot + TPM2 verifies the boot path; impermanence ensures the root filesystem is clean too. Runtime tampering cannot persist.
2. **Forces reproducibility** — if the disk dies, you only need the flake + the `/persist` volume to rebuild.
3. **Creates a natural backup inventory** — every persistent path is declared in code.
4. **Service hygiene** — stale files, leftover configs, and zombie state vanish every boot.

## Approach: btrfs Blank-Snapshot Rollback

Root stays on NVMe (no RAM pressure). The btrfs `@` subvolume is rolled back to an empty snapshot on every boot — atomic, fast, and safe to fail (if the wipe script fails, the old root is still there — stale but bootable).

### Wipe Mechanism (systemd initrd)

Since `boot.initrd.systemd.enable = true`, the traditional `postDeviceCommands` hook is unavailable. The wipe runs as `boot.initrd.systemd.services.rollback-root`:

```
cryptsetup.target (LUKS unlocked via TPM2)
  → rollback-root.service (delete @, snapshot @blank → @)
    → sysroot.mount (mount fresh @ as /)
```

The rollback script and its dependencies (btrfs-progs) must be explicitly added to `boot.initrd.systemd.storePaths` — they are not in the initrd by default.

## Btrfs Subvolume Layout

| Subvolume | Mountpoint | Wiped? | Purpose |
|-----------|------------|--------|---------|
| `@` | `/` | **Yes** | Ephemeral root |
| `@blank` | *(unmounted)* | No | Empty snapshot, rollback source |
| `@persist` | `/persist` | No | All declared persistent state |
| `@log` | `/var/log` | No | System logs (critical for headless debugging) |
| `@home` | `/home` | No | User home |
| `@nix` | `/nix` | No | Nix store |
| `@snapshots` | `/.snapshots` | No | Manual snapshots |

## Persistent Paths

### System
| Path | Type | Why |
|------|------|-----|
| `/etc/machine-id` | file | Stable identity for journalctl, dbus |
| `/etc/ssh/ssh_host_ed25519_key` | file | SSH host key — change = client rejection |
| `/etc/ssh/ssh_host_ed25519_key.pub` | file | Matching public key |
| `/var/lib/nixos` | dir | UID/GID maps — prevents ownership drift |

### Security
| Path | Type | Why |
|------|------|-----|
| `/var/lib/sbctl` | dir | Secure Boot PKI — loss = re-create keys + re-enroll in UEFI |

### Services
| Path | Type | Why |
|------|------|-----|
| `/var/lib/caddy` | dir | TLS certificates — loss triggers re-issuance (rate limited) |
| `/var/lib/tailscale` | dir | Node identity + WireGuard keys |
| `/var/lib/syncthing` | dir | Synced data + device keys + config |
| `/var/lib/paperless` | dir | Documents, DB, OCR models |
| `/var/lib/fail2ban` | dir | Ban database |

### Network
| Path | Type | Why |
|------|------|-----|
| `/etc/NetworkManager/system-connections` | dir | Saved connection profiles |
| `/var/lib/NetworkManager` | dir | DHCP state, secret_key |

## LUKS

### Keyslots

Each unlock method lives in its own keyslot — changing one doesn't affect the others.

```bash
sudo systemd-cryptenroll /dev/nvme0n1p2   # list enrolled slots
sudo cryptsetup luksDump /dev/nvme0n1p2   # full keyslot detail
sudo cryptsetup luksChangeKey /dev/nvme0n1p2  # change passphrase only
```

Keep the passphrase even with TPM2 enrolled — it's the only fallback if TPM2 fails.

### Boot unlock order

Controlled by the order in `crypttabExtraOpts`, not slot numbers. Current order: TPM2 → FIDO2 → passphrase (after `token-timeout=60`).

### LUKS header backup

If the LUKS header is corrupted, the disk is unrecoverable. Back it up and store it off the machine:

```bash
sudo cryptsetup luksHeaderBackup /dev/nvme0n1p2 \
  --header-backup-file ~/luks-header-backup.img
# Copy to Mac: scp -P 8822 nonroot@<ip>:~/luks-header-backup.img .
```

### PCR 7 and firmware updates

PCR 7 seals the TPM2 token to the current Secure Boot policy. It is stable across normal NixOS kernel/initrd upgrades. It **can change** if a UEFI firmware update modifies the Secure Boot revocation database (DBX) — in that case TPM unsealing will fail and FIDO2 fallback kicks in. Re-enroll after:

```bash
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/nvme0n1p2
```

### Testing FIDO2

TPM2 auto-unlocks before FIDO2 gets a chance. To test FIDO2:

```bash
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme0n1p2
# reboot — FIDO2 will be prompted
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/nvme0n1p2
```

## Key Design Decisions

### Keep systemd initrd

`boot.initrd.systemd.enable = true` must stay. The `crypttabExtraOpts` entries (`tpm2-device=auto`, `fido2-device=auto`) are systemd cryptsetup options — they only work in a systemd initrd.

### Local network SSH as recovery path

`networking.firewall.allowedTCPPorts = [ 8822 ]` opens SSH on all interfaces. If Tailscale loses its identity after a misconfigured reboot, local network SSH on port 8822 is still available.

### `/var/log` as separate subvolume

A dedicated `@log` subvolume ensures log history survives reboots — critical for debugging a headless server.

## Recovery

```bash
# From NixOS live USB:

# Option A: reinstall (disk layout is reproducible from flake)
sudo nix run github:nix-community/disko -- --mode destroy,format,mount ./nix/hosts/gmktec/disko.nix
sudo nixos-install --flake .#gmktec --no-root-password

# Option B: mount existing system and roll back generation
sudo cryptsetup open /dev/nvme0n1p2 cryptroot
sudo mount -o subvol=@ /dev/mapper/cryptroot /mnt
sudo mount -o subvol=@nix /dev/mapper/cryptroot /mnt/nix
nix-env -p /mnt/nix/var/nix/profiles/system --rollback
```

## Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Tailscale identity loss | Medium | Local SSH on port 8822 still works; verify `/persist/var/lib/tailscale/tailscaled.state` exists before rebooting |
| Secure Boot signing keys lost | High | Verify `/persist/var/lib/sbctl/keys/` exists before rebooting |
| Rollback service ordering wrong | High | Use `nixos-rebuild boot` + pre-reboot verification |
