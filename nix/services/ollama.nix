{ config, pkgs, lib, ... }: {

  services.ollama = {
    enable = true;
    host = "127.0.0.1";
    port = 11434;
  };

  # Sandbox additions on top of upstream ollama module — see nix/services/ollama.md
  systemd.services.ollama.serviceConfig = {
    # Override: upstream sets false for GPU access. This box has only a low-end
    # integrated Intel UHD iGPU (6W TDP) — no meaningful acceleration, CPU-only is fine.
    PrivateDevices = lib.mkForce true;

    CapabilityBoundingSet = "";

    # Allowlist filesystem: empty root, bind-mount only what Ollama needs
    TemporaryFileSystem = "/:ro";
    BindPaths = [ "/var/lib/private/ollama" ];
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

  # No firewall rule — localhost only, not exposed on Tailscale.
}
