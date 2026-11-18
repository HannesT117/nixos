{ config, pkgs, lib, ... }: {

  users.users.grist = {
    isSystemUser = true;
    group = "grist";
    home = "/var/lib/grist-core";
  };
  users.groups.grist = {};

  services.grist = {
    enable = true;
    environment = {
      PORT = "8484";
      APP_HOME_URL = "https://money.jrdn.cx";
    };
    environmentFiles = [ "/persist/secrets/grist-env" ];
  };

  systemd.services.grist-core.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "grist";
    Group = "grist";
    StateDirectory = lib.mkForce "grist-core";
    StateDirectoryMode = "0700";
  };
}
