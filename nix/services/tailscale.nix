{ config, pkgs, ... }: {

  environment.systemPackages = [ pkgs.tailscale ];

  # Tailscale client pointed at self-hosted Headscale
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";  # allows using exit nodes and subnet routes
    extraUpFlags = [ "--login-server" "https://headscale.jrdn.cx" ];
  };

  # Allow Tailscale traffic. Services open their own ports via extraInputRules
  networking.firewall = {
    allowedUDPPorts = [ config.services.tailscale.port ];  # default 41641
  };
}
