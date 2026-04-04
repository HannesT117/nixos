# n8n

Workflow automation running at `https://n8n.jrdn.cx` (Tailscale-only).

## Initial setup

Create the credentials file before first boot:

```bash
printf 'N8N_ENCRYPTION_KEY=%s\n' \
  "$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')" \
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

## Task runner (Code nodes)

n8n Code nodes require an external task runner. The runner is a separate systemd service (`n8n-task-runner`) that connects to n8n's broker on port 5679.

**Auth flow:** The broker issues one-time dynamic grant tokens, it does not accept a static shared secret directly. The runner wrapper script (`n8n-task-runner-wrapper`) handles this:

1. POSTs `{ "token": "<N8N_RUNNERS_AUTH_TOKEN>" }` to `http://127.0.0.1:5679/runners/auth`
2. Receives a short-lived grant token
3. Exports it as `N8N_RUNNERS_GRANT_TOKEN` and starts `n8n-task-runner`

The `N8N_RUNNERS_AUTH_TOKEN` must be present in `/persist/secrets/n8n-credentials` and is shared by both the n8n service and the task runner wrapper via `EnvironmentFile`.

**Note:** The Docker docs show `N8N_RUNNERS_AUTH_TOKEN` on both sides of the connection, but that applies to the `n8nio/runners` Docker image which handles the grant token exchange internally. The bundled `n8n-task-runner` binary reads `N8N_RUNNERS_GRANT_TOKEN` and requires the wrapper to fetch it first.

Add the auth token to the credentials file if not already present:

```bash
echo "N8N_RUNNERS_AUTH_TOKEN=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')" \
  | sudo tee -a /persist/secrets/n8n-credentials
```
