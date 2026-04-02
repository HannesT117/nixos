{ config, pkgs, lib, ... }: {

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

  # Systemd hardening. lib.mkForce on each value to avoid type conflicts
  # with the upstream n8n module which sets some of these using string "yes"/"no"
  systemd.services.n8n.serviceConfig = with lib; {
    ProtectSystem = mkForce "strict";
    ProtectHome = mkForce true;
    PrivateTmp = mkForce true;
    NoNewPrivileges = mkForce true;
    PrivateDevices = mkForce true;
    ProtectKernelTunables = mkForce true;
    ProtectKernelModules = mkForce true;
    ProtectKernelLogs = mkForce true;
    ProtectControlGroups = mkForce true;
    RestrictNamespaces = mkForce true;
    RestrictRealtime = mkForce true;
    LockPersonality = mkForce true;
    CapabilityBoundingSet = mkForce "";
    ReadWritePaths = mkForce [ "/var/lib/n8n" ];
    RestrictAddressFamilies = mkForce [ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" ];
    SystemCallArchitectures = mkForce "native";
  };
}
