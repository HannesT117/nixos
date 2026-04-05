{ pkgs, lib, ... }:

{
  services.caddy = {
    enable = true;

    # Caddy built with the Porkbun DNS plugin for DNS-01 ACME challenges.
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/porkbun@v0.3.1" ];
      hash = "sha256-Pb27UcjTRfGCmcCAvSZtaXNPANyeH46MeCw3APPv9uI=";
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
  };

  systemd.services.caddy.serviceConfig.EnvironmentFile = "/persist/secrets/porkbun-credentials";

  # Firewall
  networking.firewall.extraInputRules = ''
    ip saddr 100.64.0.0/24 tcp dport { 80, 443 } accept
  '';
}
