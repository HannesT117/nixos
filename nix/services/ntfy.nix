{ config, pkgs, lib, ... }: {

  users.users.ntfy-sh = {
    isSystemUser = true;
    group = "ntfy-sh";
    home = "/var/lib/ntfy-sh";
  };
  users.groups.ntfy-sh = {};

  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.jrdn.cx";
      listen-http = ":8091";
      auth-file = "/var/lib/ntfy-sh/user.db";
      auth-default-access = "deny-all";
    };
  };

  systemd.services.ntfy-sh.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "ntfy-sh";
    Group = "ntfy-sh";
    StateDirectory = lib.mkForce "ntfy-sh";
    StateDirectoryMode = "0700";
  };

  networking.firewall.extraInputRules = ''
    ip saddr 100.64.0.0/24 tcp dport 8091 accept
  '';
}
