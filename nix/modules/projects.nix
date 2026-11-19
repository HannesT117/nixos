{ config, lib, ... }:

let
  cfg = config.homelab.projects;
  readOnlyStr = default: lib.mkOption {
    type = lib.types.str;
    inherit default;
    readOnly = true;
  };
in
{
  options.homelab.projects = {
    directory = readOnlyStr "/srv/projects";
    group = readOnlyStr "projects";
    persistEntry = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      description = ''
        Impermanence entry for the projects directory: owned by the projects
        group, setgid so new files inherit it.
      '';
    };
  };

  config = {
    homelab.projects.persistEntry = {
      inherit (cfg) directory group;
      mode = "2770";
    };

    users.groups.${cfg.group} = { };

    systemd.tmpfiles.rules = [
      "z /persist${cfg.directory} ${cfg.persistEntry.mode} root ${cfg.group} -"
    ];
  };
}
