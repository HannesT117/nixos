{ config, pkgs, lib, ... }: {

  users.users.n8n = {
    isSystemUser = true;
    group = "n8n";
    home = "/var/lib/n8n";
  };
  users.groups.n8n = {};

  services.n8n = {
    enable = true;

    environment = {
      N8N_HOST = "0.0.0.0";
      N8N_PORT = "5678";
      N8N_PROTOCOL = "https";
      WEBHOOK_URL = "https://n8n.jrdn.cx";
      N8N_EDITOR_BASE_URL = "https://n8n.jrdn.cx";
      GENERIC_TIMEZONE = "Europe/Berlin";
      N8N_RUNNERS_ENABLED = "false";
    };
  };

  # Firewall
  networking.firewall.extraInputRules = ''
    ip saddr 100.64.0.0/24 tcp dport 5678 accept
  '';

  # Disable DynamicUser so impermanence can persist /var/lib/n8n directly.
  # See ./n8n.md
  systemd.services.n8n.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "n8n";
    Group = "n8n";
    StateDirectory = lib.mkForce "n8n";
    StateDirectoryMode = "0700";
    EnvironmentFile = "/persist/secrets/n8n-credentials";
    CapabilityBoundingSet = "";
    RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" ];
    SystemCallArchitectures = "native";
  };
}
