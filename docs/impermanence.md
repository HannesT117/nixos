# Impermanence for gmktec NixOS Server

## Context

The gmktec server runs NixOS with LUKS encryption, btrfs subvolumes, Secure Boot (lanzaboote), and TPM2 auto-unlock. All state currently persists on the root subvolume `@`. Over time, undeclared mutable state accumulates — config drift that makes the system non-reproducible from the flake alone.

Impermanence wipes `/` on every boot and forces all mutable state to be explicitly declared. Combined with the existing Secure Boot + TPM2 chain, this means every boot starts from a verified, known-clean state.

## Why Impermanence Makes Sense Here

1. **Completes the trust chain** — Secure Boot + TPM2 verifies the boot path; impermanence ensures the root filesystem is clean too. Runtime tampering cannot persist.
2. **Forces reproducibility** — if the disk dies, you only need the flake + the `/persist` volume to rebuild. No hidden state surprises.
3. **Creates a natural backup inventory** — every persistent path is declared in code, so you know exactly what needs backup.
4. **Service hygiene** — stale files, leftover configs, and zombie state from old service versions vanish every boot.

## Approach: btrfs Blank-Snapshot Rollback

**Not tmpfs** — tmpfs eats RAM and the server already runs memory-hungry services (Paperless OCR, Syncthing). Instead, the existing btrfs `@` subvolume is rolled back to an empty snapshot on every boot. This is:
- No RAM pressure (root stays on NVMe)
- Atomic and fast (btrfs COW)
- Safe to fail (if wipe script fails, old root is still there — stale but bootable)
- Easy to disable (remove the wipe service, reboot, full old root is back)

### Wipe Mechanism (systemd initrd)

Since `boot.initrd.systemd.enable = true`, the traditional `postDeviceCommands` hook is unavailable. The wipe runs as `boot.initrd.systemd.services.rollback-root`:

```
cryptsetup.target (LUKS unlocked via TPM2)
  → rollback-root.service (delete @, snapshot @blank → @)
    → sysroot.mount (mount fresh @ as /)
```

## Btrfs Subvolume Layout

Declared in `nix/hosts/gmktec/disko.nix` — disko creates all subvolumes and generates `fileSystems` / `boot.initrd.luks.devices` automatically. No manual `btrfs subvolume create` needed.

| Subvolume | Mountpoint | Wiped? | Purpose |
|-----------|------------|--------|---------|
| `@` | `/` | **Yes** | Ephemeral root |
| `@blank` | *(unmounted)* | No | Empty snapshot, rollback source |
| `@persist` | `/persist` | No | All declared persistent state |
| `@log` | `/var/log` | No | System logs (critical for headless debugging) |
| `@home` | `/home` | No | User home (already separate, unchanged) |
| `@nix` | `/nix` | No | Nix store (already separate, unchanged) |
| `@snapshots` | `/.snapshots` | No | Snapshots (unchanged) |

## Paths That Need Persistence

### System-critical
| Path | Type | Why |
|------|------|-----|
| `/etc/machine-id` | file | Stable identity for journalctl, dbus |
| `/etc/ssh/ssh_host_ed25519_key` | file | SSH host key — change = client rejection |
| `/etc/ssh/ssh_host_ed25519_key.pub` | file | Matching public key |
| `/etc/ssh/ssh_host_rsa_key` | file | RSA host key (if present) |
| `/etc/ssh/ssh_host_rsa_key.pub` | file | Matching public key |
| `/var/lib/nixos` | dir | UID/GID maps — prevents ownership drift |

### Security
| Path | Type | Why |
|------|------|-----|
| `/var/lib/sbctl` | dir | Secure Boot PKI bundle — loss = re-create keys + re-enroll in UEFI |

### Services

The impermanence module bind-mounts each path from `/persist/var/lib/…` to `/var/lib/…`, so services see the same paths as before and require no configuration changes.

| Path | Type | Why |
|------|------|-----|
| `/var/lib/tailscale` | dir | Node identity + WG keys |
| `/var/lib/syncthing` | dir | Synced data + device keys + config (includes CookLang recipes) |
| `/var/lib/paperless` | dir | Documents, DB, OCR models |
| `/var/lib/fail2ban` | dir | Ban database |

### Network
| Path | Type | Why |
|------|------|-----|
| `/etc/NetworkManager/system-connections` | dir | Saved connection profiles |
| `/var/lib/NetworkManager` | dir | DHCP state, secret_key |

### Dotfiles
| Path | Type | Why |
|------|------|-----|
| `/etc/dotfiles` | dir | Git sparse checkout — avoids re-clone on every boot |

## Key Design Decisions

### Keep systemd initrd

`boot.initrd.systemd.enable = true` must stay. The `crypttabExtraOpts` entries (`tpm2-device=auto`, `fido2-device=auto`) are systemd cryptsetup options — they only work in a systemd initrd. Disabling it breaks TPM2 and FIDO2 auto-unlock. The wipe mechanism therefore uses `boot.initrd.systemd.services` (not `postDeviceCommands` which only works in scripted initrd).

### Local network SSH as recovery path

`networking.firewall.allowedTCPPorts = [ 8822 ]` opens SSH on all interfaces — the server is reachable from the local network on port 8822. If Tailscale loses its identity after a misconfigured impermanence reboot, local network SSH is still available. Note the server's local IP before attempting the first impermanence reboot.

### No home-manager needed

`@home` is a separate subvolume that is not wiped. Home directory contents persist naturally. The existing stow-based dotfile management works fine.

### `/var/log` as separate subvolume

A dedicated `@log` subvolume is simpler than a bind mount and ensures log history survives reboots — critical for debugging a headless server.

---

## Install Procedure

The entire disk layout is declared in `nix/hosts/gmktec/disko.nix`. The install and post-install steps are captured in numbered scripts under `scripts/`.

### Step 1: Format and install

Boot NixOS installer USB, then:

```bash
# Clone the flake
git clone <repo-url> /tmp/nixos && cd /tmp/nixos

# Format disk — creates all partitions, LUKS, and btrfs subvolumes
# Prompts for LUKS passphrase interactively
sudo nix run github:nix-community/disko -- --mode destroy,format,mount ./nix/hosts/gmktec/disko.nix

# Install NixOS
sudo nixos-install --flake .#gmktec --no-root-password

sudo reboot
```

### Step 2: Secure Boot (`scripts/01_setupsecureboot.sh` → `scripts/01b_enrollkeys.sh`)

Two scripts, split by the required UEFI reboot in between:

**`01_setupsecureboot.sh`** — run first:
1. Generates Secure Boot signing keys (`sbctl create-keys`)
2. Builds and signs all EFI binaries (`nixos-rebuild switch` + `sbctl verify`)
3. Reboots — you enter UEFI, delete all keys (Setup Mode), enable Secure Boot, boot back

**`01b_enrollkeys.sh`** — run after returning from UEFI:
4. Verifies Setup Mode is active
5. Enrolls keys into firmware (`sbctl enroll-keys --microsoft`)
6. Reboots to activate Secure Boot enforcement

### Step 3: TPM2 LUKS auto-unlock (`scripts/02_setuptpm2.sh`)

Run after Secure Boot is confirmed active (`sbctl status` shows `Secure Boot: ✓ Enabled`):

1. Enrolls TPM2 token for LUKS (`systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7`)
2. Rebuilds to activate TPM2 config (`nixos-rebuild switch`)
3. Reboot — system auto-unlocks LUKS without passphrase or YubiKey

### What stays manual and why

| Step | Why it can't be in Nix |
|------|----------------------|
| LUKS passphrase | Secret — set interactively during disko format |
| UEFI Setup Mode | Firmware UI — no OS-level API |
| `sbctl create-keys` | Generates secrets that must stay off the Nix store |
| `sbctl enroll-keys` | Requires UEFI Setup Mode to be active |
| `systemd-cryptenroll` | Binds to specific hardware TPM PCRs |

### Recovery

```bash
# From NixOS live USB:

# Option A: reinstall (disk layout is reproducible)
sudo nix run github:nix-community/disko -- --mode destroy,format,mount ./nix/hosts/gmktec/disko.nix
sudo nixos-install --flake .#gmktec --no-root-password

# Option B: mount existing system and roll back generation
sudo cryptsetup open /dev/nvme0n1p2 cryptroot
sudo mount -o subvol=@ /dev/mapper/cryptroot /mnt
sudo mount -o subvol=@nix /dev/mapper/cryptroot /mnt/nix
nix-env -p /mnt/nix/var/nix/profiles/system --rollback
```

## Verification Checklist

- [ ] System boots and SSH is reachable (port 8822, local network + Tailscale)
- [ ] `sudo sbctl status` shows Secure Boot enabled
- [ ] `sudo tailscale status` shows node connected
- [ ] `systemctl status syncthing paperless-web` — services running
- [ ] `journalctl --list-boots` shows boot history
- [ ] Second reboot — verify root is clean (no carryover state in `/etc`, `/var`)

---

## Risks and Mitigations for existing systems

### Tailscale identity loss (MEDIUM — local SSH is fallback)
If `/var/lib/tailscale` is not persisted, the server drops off the tailnet until re-authorized on Headscale. Not a hard lockout — local network SSH on port 8822 still works.

**Mitigation**: Verify `/persist/var/lib/tailscale/tailscaled.state` exists before rebooting.

### Secure Boot signing keys
If `/var/lib/sbctl` is not persisted, `nixos-rebuild` fails (lanzaboote can't sign). Requires re-creating keys and UEFI re-enrollment.

**Mitigation**: Verify `/persist/var/lib/sbctl/keys/` exists before rebooting.

### Dotfiles activation script
The script clones into `/etc/dotfiles` (ephemeral). With the bind mount from `/persist/etc/dotfiles`, the `else` branch (fetch + reset) runs on subsequent boots. If network is unavailable during activation, the fetch fails but the existing clone is still present and stow still runs.

### systemd initrd wipe ordering
The rollback service must run after `cryptsetup.target` but before `sysroot.mount`. Wrong ordering = either no wipe (stale root, harmless) or mount failure (won't boot).

**Mitigation**: Use `nixos-rebuild boot` (not `switch`) + pre-reboot verification. Keep the safety snapshot `@snapshots/pre-impermanence` for rollback.
