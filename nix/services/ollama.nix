{ config, pkgs, lib, ... }: {

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

    # Allowlist filesystem: empty root, bind-mount only what Ollama needs
    TemporaryFileSystem = "/:ro";
    BindPaths = [ "/var/lib/ollama" ];
    BindReadOnlyPaths = [
      "/nix/store"
      "/run/systemd"
      "/proc"
      "/sys"
    ];

    MemoryMax = "8G";

    IPAddressAllow = "localhost";
    IPAddressDeny = "any";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/ollama/models 0700 ollama ollama -"
  ];

  # No firewall rule — localhost only, not exposed on Tailscale.
}
