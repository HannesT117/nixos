# NixOS

Configuration of my GMKtec homeserver. Base Setup:

- NixOS: Create reproducible builds.
- Impermanence: Wipe root on every boot. Prevents state creep.
- Secure Boot + TPM2 LUKS: Prevents booting after changes to boot chain.
- Caddy: Distribute traffic by subdomain to ports.
- Headscale + DNS Records: Use real subdomains but provide services only via VPN.

## Services

| Service | URL | Docs |
|---------|-----|------|
| Syncthing | sync.jrdn.cx | — |
| Paperless | docs.jrdn.cx | — |
| Cooklang | cook.jrdn.cx | — |
| n8n | n8n.jrdn.cx | [nix/services/n8n.md](nix/services/n8n.md) |
| Ollama | localhost:11434 | [nix/services/ollama.md](nix/services/ollama.md) |

## Cheatsheet

**Show enrolled LUKS unlock methods (password / tpm2 / fido2)**
```bash
sudo systemd-cryptenroll /dev/nvme0n1p2
```

**Show full LUKS keyslot detail**
```bash
sudo cryptsetup luksDump /dev/nvme0n1p2
```

**Change LUKS passphrase** (does not affect TPM2/FIDO2 slots)
```bash
sudo cryptsetup luksChangeKey /dev/nvme0n1p2
```

**Enroll FIDO2 key**
```bash
sudo systemd-cryptenroll --fido2-device=auto /dev/nvme0n1p2
```

**Test FIDO2 unlock** (wipe TPM2 temporarily, reboot, re-enroll after)
```bash
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme0n1p2
# reboot — FIDO2 will be prompted
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/nvme0n1p2
```

**SSH tunnel to a local service** (example: Syncthing on port 8384)
```bash
ssh -i ~/.ssh/homeserver -L 8888:127.0.0.1:8384 nonroot@192.168.178.195 -p 8822
# then open http://localhost:8888
```

---

**Apply config changes**
```bash
sudo nixos-rebuild switch --flake /etc/nixos#gmktec
```

**Test config** (active until next reboot, no boot entry created)
```bash
sudo nixos-rebuild test --flake /etc/nixos#gmktec
```

**Apply on next reboot only** (don't activate now)
```bash
sudo nixos-rebuild boot --flake /etc/nixos#gmktec
```

**Update flake inputs** (nixpkgs, lanzaboote, etc.)
```bash
cd /etc/nixos && nix flake update
```

**List system generations**
```bash
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
```

**Delete old generations and free disk space**
```bash
sudo nix-collect-garbage -d
```

**Check service status / logs**
```bash
systemctl status syncthing
journalctl -u syncthing -f        # follow logs for a service
journalctl -b                     # all logs from current boot
journalctl -b -1                  # all logs from previous boot
```

**Check impermanence rollback succeeded**
```bash
journalctl -b | grep rollback
```
