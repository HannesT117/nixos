{ config, pkgs, lib, ... }:

let
  grist = config.services.grist.environment;
in
{
  services.caddy = {
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
    virtualHosts."money.jrdn.cx".extraConfig = ''
      @apiKey header Authorization "Bearer *"
      handle @apiKey {
        request_header -${grist.GRIST_FORWARD_AUTH_HEADER}
        reverse_proxy localhost:${grist.PORT}
      }

      handle /${grist.GRIST_FORWARD_AUTH_LOGOUT_PATH} {
        redir https://auth.jrdn.cx/logout
      }

      handle {
        forward_auth localhost:9091 {
          uri /api/authz/forward-auth
          copy_headers Remote-User Remote-Groups Remote-Email>${grist.GRIST_FORWARD_AUTH_HEADER} Remote-Name
        }
        reverse_proxy localhost:${grist.PORT}
      }
    '';
  };

  systemd.services.caddy.serviceConfig.EnvironmentFile = "/persist/secrets/porkbun-credentials";

  # Firewall
  networking.firewall.extraInputRules = ''
    iifname "tailscale0" tcp dport { 80, 443 } accept
  '';
}
