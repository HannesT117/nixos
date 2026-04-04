# ntfy-sh

Push notification server running at `https://n.jrdn.cx` (Tailscale-only).

## Auth setup

Auth is `deny-all` by default. Create a user and grant topic access before sending any notifications:

```bash
ntfy user add <username>
ntfy access <username> <topic> <write|read>
```

List current access rules:

```bash
sudo -u ntfy-sh ntfy access
```

## iOS instant notifications

iOS prevents background connections, so the ntfy iOS app can't maintain a persistent connection to a self-hosted server. To get instant notifications on iOS, set `upstream-base-url = "https://ntfy.sh"` in the config.

When a message arrives, your server forwards a tiny poll request (just a message ID, no content) to ntfy.sh → Firebase → APNS → iOS app. The app then fetches the actual message from **your** server. ntfy.sh never sees your message content.

Without this setting, notifications still arrive but may be delayed up to 20–30 minutes.

## Behind proxy

`behind-proxy = true` must be set when Caddy handles TLS termination, otherwise ntfy uses the wrong base URL for iOS poll requests and the web UI shows incorrect URLs.

## Sending from n8n

Use the internal URL to avoid TLS overhead:

```
http://127.0.0.1:8091/<topic>
```

Set an `Authorization: Basic <base64(user:pass)>` header. Store the value in
`/persist/secrets/n8n-credentials` as `NTFY_AUTH=Basic <base64>` and reference
it in the workflow with `={{ $env.NTFY_AUTH }}` (requires
`N8N_ALLOWED_ENV_VARS = "NTFY_AUTH"` in `n8n.nix`).
