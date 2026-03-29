{ config, pkgs, ... }: {

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
    };
  };

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
