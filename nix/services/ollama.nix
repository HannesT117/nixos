{ config, pkgs, lib, ... }:

{
  users.users.ollama = {
    isSystemUser = true;
    group = "ollama";
    home = "/var/lib/ollama";
  };
  users.groups.ollama = {};

  services.ollama = {
    enable = true;
    host = "127.0.0.1";
    port = 11434;
    loadModels = [ "phi3:mini" ];
  };

  # Disable DynamicUser so impermanence can persist /var/lib/ollama directly.
  # Sandbox details see ./ollama.md
  systemd.services.ollama.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "ollama";
    Group = "ollama";
    StateDirectory = lib.mkForce "ollama";
    StateDirectoryMode = "0700";

    PrivateDevices = lib.mkForce true;
    CapabilityBoundingSet = "";

    # Auto-derived from impermanence: hide all other /var/lib/* service data
    InaccessiblePaths = config.homelab.sandbox.hiddenPathsFor "/var/lib/ollama";

    MemoryMax = "8G";

    # ollama needs outbound HTTPS for model pulls.
    # Inbound access is restricted by binding to 127.0.0.1 only.
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/ollama/models 0700 ollama ollama -"
  ];

  # No firewall rule — localhost only, not exposed on Tailscale.
}
