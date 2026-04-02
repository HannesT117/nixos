# n8n

Workflow automation running at `https://n8n.jrdn.cx` (Tailscale-only).

## Initial setup

Create the credentials file before first boot:

```bash
printf 'N8N_ENCRYPTION_KEY=%s\n' "$(openssl rand -hex 32)" \
  | sudo tee /persist/secrets/n8n-credentials
sudo chmod 600 /persist/secrets/n8n-credentials
```

## Encryption key

n8n encrypts all stored credentials (API keys, OAuth tokens, passwords for
integrations) at rest in its database. The key is injected via systemd
`EnvironmentFile` rather than `N8N_ENCRYPTION_KEY_FILE` so the n8n service
user never requires access to `/persist/secrets/` (which is `0700 root:root`).

**If the key is lost**, all saved credentials become unreadable and must be
re-entered in the n8n UI.

## First login

n8n has no authentication on first access — set up an owner account immediately
after first launch. Access is restricted to the Tailscale network
(`100.64.0.0/24`), so exposure is limited, but don't leave it open.
