{ config, pkgs, lib, ... }: {

  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.jrdn.cx";
      listen-http = ":8091";
      auth-file = "/var/lib/ntfy-sh/user.db";
      # Deny all by default — create users with: ntfy user add <username>
      auth-default-access = "deny-all";
    };
  };

  networking.firewall.extraInputRules = ''
    ip saddr 100.64.0.0/24 tcp dport 8091 accept
  '';
}
