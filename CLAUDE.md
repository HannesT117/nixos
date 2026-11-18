# NixOS Homelab

## Project structure

- `flake.nix` — single-host flake (gmktec)
- `nix/modules/` — shared config (impermanence, common packages)
- `nix/hosts/gmktec/` — host-specific config (boot, users, SSH)
- `nix/services/` — one `.nix` + optional `.md` per service
- `docs/` — architecture docs (impermanence, secure boot)

## Key patterns

- **Impermanence**: root is wiped every boot. Anything that must survive goes in `nix/modules/impermanence.nix` under `/persist`.
- **Secrets**: stored in `/persist/secrets/` (0700 root:root). Services access them via `EnvironmentFile`. Prefix with `-` to make optional.
- **Firewall**: nftables. Tailscale clients reach web services only through Caddy (`iifname "tailscale0"` on 80/443 in `reverse-proxy.nix`); services get no port rule of their own unless they speak something other than HTTP (e.g. Rex). Ollama is localhost-only.
- **Reverse proxy**: Caddy with Porkbun DNS-01 ACME. Subdomains in `nix/services/reverse-proxy.nix`.
- **Static users over DynamicUser**: n8n, ollama, and ntfy-sh use static system users (`isSystemUser = true`) because DynamicUser conflicts with impermanence bind mounts. Always use `DynamicUser = lib.mkForce false` when the upstream module enables it.
- **Upstream module conflicts**: NixOS upstream modules often set hardening options (e.g., `LockPersonality = "yes"`). Don't re-set what upstream already handles. Only add options the upstream doesn't set. Use `lib.mkForce` only for deliberate overrides with a comment explaining why.
- **Service sandboxes**: `homelab.sandbox.hiddenPathsFor "/var/lib/<own>"` (`nix/modules/sandbox.nix`) returns every persisted `/var/lib/*` except the service's own, plus `/persist` and `/media`. Ollama and Rex use it as `InaccessiblePaths`. No manual maintenance needed when adding services.

## Hardware

GMKTec NucBox G3 Plus: Intel N-series quad-core (3.6 GHz, 6W TDP), 16 GB DDR4, Intel UHD iGPU (unused), NVMe SSD with LUKS2 + btrfs.

## Deploy

```bash
sudo nixos-rebuild switch --flake /etc/nixos#gmktec
```

## Adding a service

1. Create `nix/services/<name>.nix` (static user, hardening; a firewall rule only for non-HTTP ports)
2. Import in `nix/hosts/gmktec/default.nix`
3. Persist state in `nix/modules/impermanence.nix` (auto-hidden from sandboxed services)
4. Add Caddy virtualHost if needed
5. Add secrets to `/persist/secrets/` if needed
