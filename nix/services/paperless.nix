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
    ReadWritePaths = [ "/var/lib/paperless" ];
  };

  systemd.services.paperless-consumer.serviceConfig = {
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    NoNewPrivileges = true;
    ReadWritePaths = [ "/var/lib/paperless" ];
  };
}
