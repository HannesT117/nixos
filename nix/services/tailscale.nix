{ config, pkgs, ... }: {

  environment.systemPackages = [ pkgs.tailscale ];

  # Tailscale client pointed at self-hosted Headscale
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";  # allows using exit nodes and subnet routes
    extraUpFlags = [ "--login-server" "https://headscale.jrdn.cx" ];
  };

  # Allow Tailscale traffic through the firewall
  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ config.services.tailscale.port ];  # default 41641
  };
}
