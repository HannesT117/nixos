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

  # Create media subdirectories, owned by jellyfin so it can scan them
  systemd.tmpfiles.rules = [
    "d /media 0775 jellyfin jellyfin -"
    "d /media/movies 0775 jellyfin jellyfin -"
    "d /media/documentaries 0775 jellyfin jellyfin -"
    "d /media/tv 0775 jellyfin jellyfin -"
    "d /media/music 0775 jellyfin jellyfin -"
  ];

  # Disable DynamicUser so impermanence can persist /var/lib/jellyfin directly.
  systemd.services.jellyfin.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "jellyfin";
    Group = "jellyfin";
    StateDirectory = lib.mkForce "jellyfin";
    StateDirectoryMode = "0700";
  };
}
