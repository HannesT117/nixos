# Ollama

Local LLM inference running at `http://127.0.0.1:11434` (localhost only).
Accessible to local services via the OpenAI-compatible API. Not exposed on Tailscale.

## Sandbox model

Ollama runs in a maximally restricted systemd sandbox:

- **`TemporaryFileSystem = "/"`**: starts with an empty read-only root; nothing
  from the real filesystem is visible by default.
- **`BindPaths`**: only `/var/lib/private/ollama` (model storage) is writable.
- **`BindReadOnlyPaths`**: only `/nix/store`, `/run/systemd`, `/proc`, `/sys`
  are visible read-only.
- **`IPAddressDeny = any` / `IPAddressAllow = localhost`**: no outbound network;
  cannot exfiltrate data or reach other services.
- **`CapabilityBoundingSet = ""`**: all Linux capabilities dropped.

The model only ever sees data explicitly passed to it via the API.

## Pulling models

The IP restriction blocks `ollama pull`. To add a model:

```bash
# 1. Temporarily comment out IPAddressAllow/IPAddressDeny in ollama.nix, then:
sudo nixos-rebuild switch --flake /etc/nixos#gmktec

# 2. Pull the model
ollama pull phi3:mini        # ~2.3 GB, good general-purpose small model
# or: qwen2.5:3b, gemma2:2b, llama3.2:3b

# 3. Restore the IP lines in ollama.nix and rebuild
sudo nixos-rebuild switch --flake /etc/nixos#gmktec
```

## Recommended models for this hardware

GMKTec NucBox G3 Plus: Intel N-series quad-core, 16 GB DDR4, CPU-only inference.

| Model | Size | Speed (est.) | Notes |
|-------|------|--------------|-------|
| `phi3:mini` | 2.3 GB | ~10–15 tok/s | Best quality/size ratio |
| `qwen2.5:3b` | 2.0 GB | ~10–15 tok/s | Strong multilingual (de+en) |
| `gemma2:2b` | 1.6 GB | ~15–20 tok/s | Fastest option |
| `llama3.2:3b` | 2.0 GB | ~10–15 tok/s | Meta's compact model |

7B+ models will work but run at ~2–5 tok/s — usable for background batch tasks,
not interactive use.

## Connecting from service

Use the **OpenAI** node or **HTTP Request** node with base URL:
`http://127.0.0.1:11434/v1`

Ollama's API is OpenAI-compatible, no auth token required for localhost.
