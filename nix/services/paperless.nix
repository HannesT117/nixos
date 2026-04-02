{ config, pkgs, ... }:

let
  jq = "${pkgs.jq}/bin/jq";
  curl = "${pkgs.curl}/bin/curl";
  grep = "${pkgs.gnugrep}/bin/grep";

  classifyScript = pkgs.writeShellScript "paperless-classify" ''
    set -euo pipefail

    DOC_ID="$1"
    BASE="http://localhost:8000"

    if [ -z "''${PAPERLESS_API_TOKEN:-}" ]; then
      echo "paperless-classify: no API token configured, skipping" >&2
      exit 0
    fi

    AUTH="Authorization: Token $PAPERLESS_API_TOKEN"

    DOC_JSON=$(${curl} -sf -H "$AUTH" "$BASE/api/documents/$DOC_ID/")
    TAGS_JSON=$(${curl} -sf -H "$AUTH" "$BASE/api/tags/?page_size=200")
    CORRESP_JSON=$(${curl} -sf -H "$AUTH" "$BASE/api/correspondents/?page_size=200")
    DOCTYPE_JSON=$(${curl} -sf -H "$AUTH" "$BASE/api/document_types/?page_size=200")

    CONTENT=$(printf '%s' "$DOC_JSON" | ${jq} -r '.content // empty')
    if [ -z "''${CONTENT:-}" ]; then
      echo "paperless-classify: no content for document $DOC_ID, skipping" >&2
      exit 0
    fi

    # Build the Ollama payload entirely in jq — no shell interpolation of untrusted data
    PAYLOAD=$(printf '%s\n%s\n%s\n%s' "$TAGS_JSON" "$CORRESP_JSON" "$DOCTYPE_JSON" "$DOC_JSON" \
      | ${jq} -sc '
      (.[0].results // [] | [.[].name]) as $tags |
      (.[1].results // [] | [.[].name]) as $correspondents |
      (.[2].results // [] | [.[].name]) as $doc_types |
      (.[3].content // "" | .[0:2000]) as $content |
      {
        model: "phi3:mini",
        stream: false,
        prompt: (
          "You are classifying a document for a personal document archive.\n" +
          "Based on the document text below, select:\n" +
          "- tags: from this list: " + ($tags | join(", ")) + "\n" +
          "- correspondent: from this list: " + ($correspondents | join(", ")) + "\n" +
          "- document_type: from this list: " + ($doc_types | join(", ")) + "\n\n" +
          "Reply with ONLY a JSON object like:\n" +
          "{\"tags\": [\"tax-2025\"], \"correspondent\": \"Insurance\", \"document_type\": \"Invoice\", \"confident\": true}\n\n" +
          "Rules:\n" +
          "- Only use names from the lists above. Do not invent new ones.\n" +
          "- Set correspondent and document_type to null if none fit.\n" +
          "- Set \"confident\" to false if you are unsure about any field.\n" +
          "- Do not explain, do not add any other text.\n\n" +
          "Document:\n" + $content
        )
      }
    ')

    RESPONSE=$(${curl} -sf http://localhost:11434/api/generate \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" \
      | ${jq} -r '.response // ""')

    # Extract JSON object from response (LLM may add surrounding text)
    LLM_JSON=$(printf '%s' "$RESPONSE" | ${grep} -o '{.*}' | head -1 || echo "{}")

    # Resolve tag names to IDs, add "review" tag if LLM is not confident
    CONFIDENT=$(printf '%s' "$LLM_JSON" | ${jq} -r '.confident // false')

    PATCH_BODY=$(printf '%s\n%s\n%s\n%s\n%s' \
      "$LLM_JSON" "$TAGS_JSON" "$CORRESP_JSON" "$DOCTYPE_JSON" "$CONFIDENT" \
      | ${jq} -sc '
      (.[0]) as $llm |
      (.[1].results // []) as $tags |
      (.[2].results // []) as $correspondents |
      (.[3].results // []) as $doc_types |

      # Resolve tag names to IDs
      ([$tags[] | select(.name as $n | ($llm.tags // []) | index($n) != null) | .id]) as $tag_ids |

      # Add "review" tag if not confident
      (if ($llm.confident | not) then
        ($tags[] | select(.name == "review") | .id) // null
      else null end) as $review_id |

      # Merge tag IDs
      (if $review_id then ($tag_ids + [$review_id]) else $tag_ids end | unique) as $final_tags |

      # Resolve correspondent
      ([$correspondents[] | select(.name == ($llm.correspondent // "")) | .id] | first // null) as $corresp_id |

      # Resolve document type
      ([$doc_types[] | select(.name == ($llm.document_type // "")) | .id] | first // null) as $doctype_id |

      # Build patch — only include fields the LLM actually set
      {}
      + (if ($final_tags | length) > 0 then {tags: $final_tags} else {} end)
      + (if $corresp_id then {correspondent: $corresp_id} else {} end)
      + (if $doctype_id then {document_type: $doctype_id} else {} end)
    ')

    if [ "$PATCH_BODY" = "{}" ]; then
      echo "paperless-classify: nothing to apply for document $DOC_ID" >&2
      exit 0
    fi

    ${curl} -sf -X PATCH "$BASE/api/documents/$DOC_ID/" \
      -H "$AUTH" \
      -H "Content-Type: application/json" \
      -d "$PATCH_BODY" > /dev/null

    echo "paperless-classify: doc $DOC_ID — applied $PATCH_BODY" >&2
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
      PAPERLESS_CONSUMER_OWNER = "jo";
      PAPERLESS_POST_CONSUME_SCRIPT = toString classifyScript;
    };
  };

  # Ensure classifyScript derivation is in the system closure
  systemd.services.paperless-task-queue.path = [ classifyScript ];

  # API token for the classify script, runs in task-queue, not consumer
  systemd.services.paperless-task-queue.serviceConfig.EnvironmentFile =
    "-/persist/secrets/paperless-api-token";

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
