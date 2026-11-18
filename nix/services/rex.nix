{ inputs, pkgs, config, ... }:

let
  clientAddresses = [ "100.64.0.1" "fd7a:115c:a1e0::1" ];
in
{
  imports = [ inputs.rex.nixosModules.default ];

  services.rex = {
    enable = true;
    extraListen = [ "tailnet://:7297" ];
    logFormat = "json";
  };

  users.users.rex = {
    shell = pkgs.zsh;
    packages = [ pkgs.claude-code ];
  };

  systemd.services.rex = {
    restartIfChanged = false;
    serviceConfig = {
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ];
      InaccessiblePaths = config.homelab.sandbox.hiddenPathsFor "/var/lib/rex";
      IPAddressDeny = [
        "localhost"
        "10.0.0.0/8"
        "172.16.0.0/12"
        "192.168.0.0/16"
        "100.64.0.0/10"
        "fe80::/10"
        "fc00::/7"
      ];
      IPAddressAllow = clientAddresses ++ [ "100.100.100.100" ];
      MemoryMax = "4G";
      OOMPolicy = "continue";
      TasksMax = 512;
    };
  };

  networking.firewall.extraInputRules = ''
    iifname "tailscale0" tcp dport 7297 accept
  '';
}
