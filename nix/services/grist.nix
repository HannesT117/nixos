{ config, pkgs, lib, ... }:

let
  port = "8484";
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

  networking.firewall.extraCommands = ''
    ip46tables -N grist-local 2>/dev/null || true
    ip46tables -F grist-local
    ip46tables -A grist-local -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
    ip46tables -A grist-local -m owner --uid-owner caddy -j RETURN
    ip46tables -A grist-local -m owner --uid-owner grist -j RETURN
    ip46tables -A grist-local -p tcp -j REJECT --reject-with tcp-reset
    ip46tables -C OUTPUT -o lo -p tcp --dport ${port} -j grist-local 2>/dev/null \
      || ip46tables -A OUTPUT -o lo -p tcp --dport ${port} -j grist-local
  '';
  networking.firewall.extraStopCommands = ''
    ip46tables -D OUTPUT -o lo -p tcp --dport ${port} -j grist-local 2>/dev/null || true
    ip46tables -F grist-local 2>/dev/null || true
    ip46tables -X grist-local 2>/dev/null || true
  '';

  systemd.services.grist-core.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "grist";
    Group = "grist";
    StateDirectory = lib.mkForce "grist-core";
    StateDirectoryMode = "0700";
  };
}
