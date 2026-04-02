# Paperless

Document management running at `https://docs.jrdn.cx` (Tailscale-only).

## Syncthing inbox

Documents dropped into the shared Syncthing folder on your laptop are synced
directly to `/var/lib/paperless/consume` on the server. Paperless polls that
directory every 60 seconds and ingests whatever it finds.

The consume directory is `2770 paperless:paperless` (setgid) so files written
by the `syncthing` user (which is a member of the `paperless` group) inherit
the correct group and are readable by the consumer.

Configure the Syncthing shared folder on your laptop to point to
`/var/lib/paperless/consume` on the server (done in the Syncthing UI).

## Ollama classification

After each document is ingested and OCR'd, `PAPERLESS_POST_CONSUME_SCRIPT`
runs `paperless-classify`:

1. Fetches the document's OCR text from the Paperless API (`/api/documents/{id}/`)
2. Fetches all existing tags from Paperless (`/api/tags/`)
3. Sends the tag list + first 2000 chars of document text to Ollama (`phi3:mini`)
4. Parses Ollama's response for a JSON array of tag names
5. Resolves names to IDs — names Ollama invented that don't exist are silently ignored
6. Applies matching tags via `PATCH /api/documents/{id}/`

The script fails gracefully: if Ollama is unreachable or returns unparseable
output, the document is still ingested (just without auto-tags).

Only existing tags are applied — the script never creates new ones. Create your
tags in the Paperless UI first, then the classifier will pick from them.

## API token setup

The classify script authenticates against the Paperless REST API using a token
stored in `/persist/secrets/paperless-api-token`.

After first login to the Paperless UI:
1. Go to **Settings → API Tokens** and copy your token
2. Store it on the server:
```bash
echo "PAPERLESS_API_TOKEN=<token>" | sudo tee /persist/secrets/paperless-api-token
sudo chmod 600 /persist/secrets/paperless-api-token
```

## Logs

```bash
journalctl -u paperless-consumer -f   # follow consumer + classify script output
```
