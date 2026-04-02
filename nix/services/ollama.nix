{ config, pkgs, ... }: {

  services.ollama = {
    enable = true;
    host = "127.0.0.1";
    port = 11434;
  };

  # Sandbox and model-pull instructions — see docs/ollama.md
  systemd.services.ollama.serviceConfig = {
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    NoNewPrivileges = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    RestrictNamespaces = true;
    RestrictRealtime = true;
    LockPersonality = true;
    SystemCallArchitectures = "native";
    RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
    CapabilityBoundingSet = "";

    # Allowlist: empty root filesystem, bind-mount only what Ollama needs
    TemporaryFileSystem = "/:ro";
    BindPaths = [ "/var/lib/private/ollama" ];
    BindReadOnlyPaths = [
      "/nix/store"
      "/run/systemd"  # systemd integration only, not all of /run
      "/proc"
      "/sys"
    ];

    # Memory limit: leave room for other services
    MemoryMax = "8G";

    IPAddressAllow = "localhost";
    IPAddressDeny = "any";
  };

  # No firewall rule — localhost only, not exposed on Tailscale.
}
