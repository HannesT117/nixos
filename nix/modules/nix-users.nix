{ config, lib, ... }:

let
  group = config.homelab.nixUsers.group;
in
{
  options.homelab.nixUsers.group = lib.mkOption {
    type = lib.types.str;
    default = "nix-users";
    readOnly = true;
  };

  config = {
    users.groups.${group} = { };
    nix.settings.allowed-users = [ "@wheel" "@${group}" ];
  };
}
