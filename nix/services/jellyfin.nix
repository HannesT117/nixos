{ config, lib, ... }:

{
  users.users.jellyfin = {
    isSystemUser = true;
    group = "jellyfin";
    home = "/var/lib/jellyfin";
  };
  users.groups.jellyfin = {};

  services.jellyfin = {
    enable = true;
    openFirewall = false;
  };

  # Disable DynamicUser so impermanence can persist /var/lib/jellyfin directly.
  systemd.services.jellyfin.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "jellyfin";
    Group = "jellyfin";
    StateDirectory = lib.mkForce "jellyfin";
    StateDirectoryMode = "0700";
  };

  networking.firewall.extraInputRules = ''
    ip saddr 100.64.0.0/24 tcp dport 8096 accept
  '';
}
