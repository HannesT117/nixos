{ config, pkgs, lib, ... }:

let
  onlyCaddy = "meta skuid != caddy";
in
{
  options.homelab.caddy.onlyCaddy = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    description = ''
      nftables match for traffic from any user other than caddy. Use it in
      output rules that restrict a loopback port to Caddy; the build-time
      ruleset check swaps it for a user that exists in the build sandbox.
    '';
  };

  config.homelab.caddy.onlyCaddy = onlyCaddy;

  config.services.caddy = {
    enable = true;

    # Caddy built with the Porkbun DNS plugin for DNS-01 ACME challenges.
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/porkbun@v0.3.1" ];
      hash = "sha256-8DrezGjdIUq9tBvbK7UuVDeQPuzUdBsmIkI79YDCTOQ=";
    };

    # Use DNS-01 challenge globally, credentials injected via EnvironmentFile
    globalConfig = ''
      acme_dns porkbun {
        api_key {env.PORKBUN_API_KEY}
        api_secret_key {env.PORKBUN_SECRET_API_KEY}
      }
    '';

    virtualHosts."cook.jrdn.cx".extraConfig = "reverse_proxy localhost:9080";
    virtualHosts."sync.jrdn.cx".extraConfig = "reverse_proxy localhost:8384";
    virtualHosts."docs.jrdn.cx".extraConfig = "reverse_proxy localhost:8000";
    virtualHosts."n8n.jrdn.cx".extraConfig = "reverse_proxy localhost:5678";
    virtualHosts."n.jrdn.cx".extraConfig = "reverse_proxy localhost:8091";
    virtualHosts."media.jrdn.cx".extraConfig = "reverse_proxy localhost:8096";
    virtualHosts."auth.jrdn.cx".extraConfig = "reverse_proxy localhost:9091";
  };

  config.systemd.services.caddy.serviceConfig.EnvironmentFile = "/persist/secrets/porkbun-credentials";

  config.networking.firewall.extraInputRules = ''
    iifname "tailscale0" tcp dport { 80, 443 } accept
  '';

  config.networking.nftables.tables.caddy-admin-local = {
    family = "inet";
    content = ''
      chain output {
        type filter hook output priority filter; policy accept;
        oifname "lo" tcp dport 2019 ct state new ${onlyCaddy} reject with tcp reset
      }
    '';
  };

  config.networking.nftables.preCheckRuleset = ''
    sed -i 's/${onlyCaddy}/meta skuid != root/' ruleset.conf
  '';
}
