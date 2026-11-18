{ config, pkgs, lib, ... }:

let
  port = "8484";
  localClients = "meta skuid != { caddy, grist }";
in
{
  users.users.grist = {
    isSystemUser = true;
    group = "grist";
    home = "/var/lib/grist-core";
  };
  users.groups.grist = {};

  services.grist = {
    enable = true;
    environment = {
      PORT = port;
      APP_HOME_URL = "https://money.jrdn.cx";
      APP_HOME_INTERNAL_URL = "http://localhost:${port}";
      GRIST_FORWARD_AUTH_HEADER = "Remote-Email";
      GRIST_FORWARD_AUTH_LOGOUT_PATH = "_logout";
      GRIST_IGNORE_SESSION = "true";
      GRIST_FORCE_LOGIN = "true";
    };
    environmentFiles = [ "/persist/secrets/grist-env" ];
  };

  networking.nftables.tables.grist-local = {
    family = "inet";
    content = ''
      chain output {
        type filter hook output priority filter; policy accept;
        oifname "lo" tcp dport ${port} ct state new ${localClients} reject with tcp reset
      }
    '';
  };
  networking.nftables.preCheckRuleset = ''
    sed -i 's/${localClients}/meta skuid != { root, nobody }/' ruleset.conf
  '';

  systemd.services.grist-core.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "grist";
    Group = "grist";
    StateDirectory = lib.mkForce "grist-core";
    StateDirectoryMode = "0700";
  };
}
