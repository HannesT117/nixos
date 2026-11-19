{ config, lib, ... }:

let
  persistence = config.environment.persistence."/persist";
  userHomes = map (name: config.users.users.${name}.home) (lib.attrNames persistence.users);
  serviceStatePaths = builtins.filter (lib.hasPrefix "/var/lib/")
    (map (d: d.dirPath) persistence.directories ++ userHomes);
in
{
  options.homelab.sandbox.hiddenPathsFor = lib.mkOption {
    type = lib.types.functionTo (lib.types.listOf lib.types.str);
    readOnly = true;
    description = ''
      Paths a sandboxed service must not see, given its own state directory:
      every other persisted /var/lib/* directory or user home with persisted
      entries, plus /persist and /media.
      Use the result as the unit's InaccessiblePaths.
    '';
  };

  config.homelab.sandbox.hiddenPathsFor = ownStateDir:
    builtins.filter (p: p != ownStateDir) serviceStatePaths ++ [ "/persist" "/media" ];
}
