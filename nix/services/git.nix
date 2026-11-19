{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.git;
  git = "${pkgs.git}/bin/git";

  preReceive = name: repo: pkgs.writeShellScript "git-pre-receive-${name}" ''
    set -euo pipefail
    reject() { echo "rejected: $*" >&2; exit 1; }
    zero='^0+$'
    tree=$(mktemp)
    trap 'rm -f "$tree"' EXIT
    while read -r _ newSha ref; do
      [ "$ref" = refs/heads/main ] || reject "only refs/heads/main is accepted, not $ref"
      [[ $newSha =~ $zero ]] && reject "main cannot be deleted"
      ${lib.optionalString repo.requireEncryption ''
        commits=$(${git} rev-list "$newSha" --not --all)
        for commit in $commits; do
          ${git} ls-tree -r -z --full-tree "$commit" > "$tree"
          while IFS= read -r -d "" entry; do
            path=''${entry#*$'\t'}
            read -r mode type sha <<< "''${entry%%$'\t'*}"
            [ "$path" = .gitattributes ] && continue
            [ "$type" = blob ] && [ "$mode" != 120000 ] || reject "$path in $commit is not a regular file"
            magic=$(head -c 10 < <(${git} cat-file blob "$sha") | od -An -c | tr -d ' \n')
            [ "$magic" = '\0GITCRYPT\0' ] || reject "$path in $commit is not git-crypt encrypted"
          done < "$tree"
        done
      ''}
    done
  '';
in
{
  options.homelab.git = {
    directory = lib.mkOption {
      type = lib.types.str;
      default = "/srv/git";
      readOnly = true;
    };
    service = lib.mkOption {
      type = lib.types.str;
      default = "git-repos.service";
      readOnly = true;
      description = "The unit that creates the hosted repositories.";
    };
    repos = lib.mkOption {
      default = { };
      description = ''
        Bare repositories served over SSH as git@<host>:<name>.git, accepting
        pushes to main only.
      '';
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          requireEncryption = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Reject any pushed file except .gitattributes that isn't git-crypt encrypted.";
          };
          path = lib.mkOption {
            type = lib.types.str;
            default = "${cfg.directory}/${name}.git";
            readOnly = true;
          };
        };
      }));
    };
    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
    persistEntry = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
    };
  };

  config = {
    homelab.git.persistEntry = {
      inherit (cfg) directory;
      user = "git";
      group = "git";
      mode = "0700";
    };

    users.groups.git = { };
    users.users.git = {
      isSystemUser = true;
      group = "git";
      home = cfg.directory;
      shell = "${pkgs.git}/bin/git-shell";
      openssh.authorizedKeys.keys = map (key: "restrict ${key}") cfg.authorizedKeys;
    };

    services.openssh.settings.AllowUsers = [ "git" ];

    systemd.services.${lib.removeSuffix ".service" cfg.service} = {
      description = "Create the hosted bare git repositories";
      wantedBy = [ "multi-user.target" ];
      unitConfig.RequiresMountsFor = [ cfg.directory ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "git";
        Group = "git";
      };
      script = lib.concatStrings (lib.mapAttrsToList (name: repo: ''
        [ -d ${repo.path} ] || ${git} init --quiet --bare --initial-branch=main ${repo.path}
        ${git} -C ${repo.path} config receive.fsckObjects true
        ${git} -C ${repo.path} config receive.denyNonFastForwards true
        ${git} -C ${repo.path} config receive.denyDeletes true
        ln -sfn ${preReceive name repo} ${repo.path}/hooks/pre-receive
      '') cfg.repos);
    };
  };
}
