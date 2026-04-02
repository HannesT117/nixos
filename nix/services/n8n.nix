{ config, pkgs, ... }: {

  services.n8n = {
    enable = true;

    environment = {
      N8N_HOST = "0.0.0.0";
      N8N_PORT = "5678";
      N8N_PROTOCOL = "https";
      WEBHOOK_URL = "https://n8n.jrdn.cx";
      N8N_EDITOR_BASE_URL = "https://n8n.jrdn.cx";
      GENERIC_TIMEZONE = "Europe/Berlin";
    };
  };

  # Firewall
  networking.firewall.extraInputRules = ''
    ip saddr 100.64.0.0/24 tcp dport 5678 accept
  '';

  # Encryption key — see docs/n8n.md
  systemd.services.n8n.serviceConfig.EnvironmentFile = "/persist/secrets/n8n-credentials";

  # Systemd hardening
  systemd.services.n8n.serviceConfig = {
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
    CapabilityBoundingSet = "";
    ReadWritePaths = [ "/var/lib/n8n" ];
    RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" ];
    SystemCallArchitectures = "native";
  };
}
