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
- **Firewall**: all services restrict to Tailscale (`ip saddr 100.64.0.0/24`). Ollama is localhost-only (no firewall rule).
- **Reverse proxy**: Caddy with Porkbun DNS-01 ACME. Subdomains in `nix/services/reverse-proxy.nix`.
- **Static users over DynamicUser**: n8n, ollama, and ntfy-sh use static system users (`isSystemUser = true`) because DynamicUser conflicts with impermanence bind mounts. Always use `DynamicUser = lib.mkForce false` when the upstream module enables it.
- **Upstream module conflicts**: NixOS upstream modules often set hardening options (e.g., `LockPersonality = "yes"`). Don't re-set what upstream already handles. Only add options the upstream doesn't set. Use `lib.mkForce` only for deliberate overrides with a comment explaining why.
- **Ollama sandbox**: `InaccessiblePaths` is auto-derived from impermanence config — every persisted `/var/lib/*` except ollama's own is hidden. No manual maintenance needed when adding services.

## Hardware

GMKTec NucBox G3 Plus: Intel N-series quad-core (3.6 GHz, 6W TDP), 16 GB DDR4, Intel UHD iGPU (unused), NVMe SSD with LUKS2 + btrfs.

## Deploy

```bash
sudo nixos-rebuild switch --flake /etc/nixos#gmktec
```

## Adding a service

1. Create `nix/services/<name>.nix` (static user, hardening, firewall rule)
2. Import in `nix/hosts/gmktec/default.nix`
3. Persist state in `nix/modules/impermanence.nix` (auto-hidden from ollama)
4. Add Caddy virtualHost if needed
5. Add secrets to `/persist/secrets/` if needed
