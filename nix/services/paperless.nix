{ config, pkgs, ... }:

let
  classifyScript = pkgs.writeShellScript "paperless-classify" ''
    set -euo pipefail

    DOC_ID="$DOCUMENT_ID"
    BASE="http://localhost:8000"
    AUTH="Authorization: Token $PAPERLESS_API_TOKEN"

    CONTENT=$(${pkgs.curl}/bin/curl -sf -H "$AUTH" "$BASE/api/documents/$DOC_ID/" \
      | ${pkgs.jq}/bin/jq -r '.content // ""')

    TAGS_JSON=$(${pkgs.curl}/bin/curl -sf -H "$AUTH" "$BASE/api/tags/?page_size=200" \
      | ${pkgs.jq}/bin/jq '[.results[] | {id, name}]')

    if [ -z "$CONTENT" ]; then
      echo "paperless-classify: no content for document $DOC_ID, skipping" >&2
      exit 0
    fi

    TAG_NAMES=$(echo "$TAGS_JSON" | ${pkgs.jq}/bin/jq -r '[.[].name] | join(", ")')

    PROMPT="You are classifying a document for a personal document archive. \
Based on the document text below, select the most relevant tags from this list: $TAG_NAMES. \
Reply with ONLY a JSON array of tag names, e.g. [\"invoices\",\"insurance\"]. \
If no tags fit, reply with []. Do not explain, do not add any other text.

Document:
$(echo "$CONTENT" | head -c 2000)"

    PAYLOAD=$(${pkgs.jq}/bin/jq -nc --arg prompt "$PROMPT" \
      '{model:"phi3:mini", prompt:$prompt, stream:false}')

    RESPONSE=$(${pkgs.curl}/bin/curl -sf http://localhost:11434/api/generate \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" \
      | ${pkgs.jq}/bin/jq -r '.response // ""')

    SUGGESTED=$(echo "$RESPONSE" | ${pkgs.grep}/bin/grep -o '\[.*\]' | head -1 || echo "[]")

    TAG_IDS=$(echo "$TAGS_JSON" | ${pkgs.jq}/bin/jq --argjson suggested "$SUGGESTED" \
      '[.[] | select(.name as $n | $suggested | index($n) != null) | .id]')

    if [ "$TAG_IDS" = "[]" ]; then
      echo "paperless-classify: no matching tags found for document $DOC_ID" >&2
      exit 0
    fi

    ${pkgs.curl}/bin/curl -sf -X PATCH "$BASE/api/documents/$DOC_ID/" \
      -H "$AUTH" \
      -H "Content-Type: application/json" \
      -d "{\"tags\": $TAG_IDS}" > /dev/null

    echo "paperless-classify: applied tags $TAG_IDS to document $DOC_ID" >&2
  '';
in
{
  services.paperless = {
    enable = true;
    dataDir = "/var/lib/paperless";

    address = "0.0.0.0"; # Has to be open to be accessible via interfaces like tailscale
    port = 8000;

    settings = {
      PAPERLESS_OCR_LANGUAGE = "deu+eng";
      PAPERLESS_OCR_LANGUAGES = "deu eng";
      PAPERLESS_OCR_SKIP_ARCHIVE_FILE = "with_text";
      PAPERLESS_TIME_ZONE = "Europe/Berlin";
      PAPERLESS_CONSUMER_POLLING = 60;
      PAPERLESS_ALLOWED_HOSTS = "docs.jrdn.cx";
      PAPERLESS_CSRF_TRUSTED_ORIGINS = "https://docs.jrdn.cx";
      PAPERLESS_POST_CONSUME_SCRIPT = classifyScript;
    };
  };

  # See nix/services/paperless.md for setup instructions
  systemd.services.paperless-consumer.serviceConfig.EnvironmentFile =
    "/persist/secrets/paperless-api-token";

  systemd.tmpfiles.rules = [
    "d /var/lib/paperless/consume 2770 paperless paperless -"
  ];

  # Daily backup: export documents, rsync to syncthing with hard-link dedup
  systemd.services.paperless-backup = {
    description = "Paperless backup to Syncthing";
    after = [ "paperless-web.service" ];
    path = [ pkgs.rsync ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = let
        backupScript = pkgs.writeShellScript "paperless-backup" ''
          set -euo pipefail

          EXPORT_DIR=/var/lib/paperless/export
          BACKUP_DIR=/var/lib/syncthing/paperless-backup
          TIMESTAMP=$(date "+%Y-%m-%dT%H-%M-%S")

          mkdir -p "$EXPORT_DIR" "$BACKUP_DIR"

          # Export all documents (runs as root — needs read access to paperless DB)
          /var/lib/paperless/paperless-manage document_exporter "$EXPORT_DIR"

          # Incremental rsync with hard-link dedup
          rsync -a --delete \
            --link-dest="$BACKUP_DIR/current/" \
            "$EXPORT_DIR/" "$BACKUP_DIR/$TIMESTAMP"

          # Atomic symlink update
          ln -snf "$TIMESTAMP" "$BACKUP_DIR/current"

          # Ensure syncthing can read the backup
          chown -R syncthing:syncthing "$BACKUP_DIR"
        '';
      in backupScript;
    };
  };

  systemd.timers.paperless-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;          # run on next boot if missed
      RandomizedDelaySec = "1h";  # avoid exact-midnight thundering herd
    };
  };

  # Firewall
  networking.firewall.extraInputRules = ''
    ip saddr 100.64.0.0/24 tcp dport 8000 accept
  '';

  # Systemd hardening
  systemd.services.paperless-web.serviceConfig = {
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    NoNewPrivileges = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    RestrictNamespaces = true;
    RestrictRealtime = true;
    LockPersonality = true;
    ReadWritePaths = [ "/var/lib/paperless" ];
  };

  systemd.services.paperless-scheduler.serviceConfig = {
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    NoNewPrivileges = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    RestrictNamespaces = true;
    RestrictRealtime = true;
    LockPersonality = true;
    ReadWritePaths = [ "/var/lib/paperless" ];
  };

  systemd.services.paperless-consumer.serviceConfig = {
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    NoNewPrivileges = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    RestrictNamespaces = true;
    RestrictRealtime = true;
    LockPersonality = true;
    ReadWritePaths = [ "/var/lib/paperless" ];
  };
}
