{ config, lib, ... }:

let
  persistedDirs = config.environment.persistence."/persist".directories;
  dirPath = d: if builtins.isString d then d else d.directory;
  serviceStatePaths = builtins.filter (lib.hasPrefix "/var/lib/") (map dirPath persistedDirs);
in
{
  options.homelab.sandbox.hiddenPathsFor = lib.mkOption {
    type = lib.types.functionTo (lib.types.listOf lib.types.str);
    readOnly = true;
    description = ''
      Paths a sandboxed service must not see, given its own state directory:
      every other persisted /var/lib/* directory, plus /persist and /media.
      Use the result as the unit's InaccessiblePaths.
    '';
  };

  config.homelab.sandbox.hiddenPathsFor = ownStateDir:
    builtins.filter (p: p != ownStateDir) serviceStatePaths ++ [ "/persist" "/media" ];
}
