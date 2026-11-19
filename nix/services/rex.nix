{ inputs, pkgs, lib, config, ... }:

let
  clientAddresses = [ "100.64.0.1" "fd7a:115c:a1e0::1" ];

  gitHookNames = [
    "applypatch-msg" "pre-applypatch" "post-applypatch" "pre-commit" "pre-merge-commit"
    "prepare-commit-msg" "commit-msg" "post-commit" "pre-rebase" "post-checkout"
    "post-merge" "pre-push" "pre-auto-gc" "post-rewrite" "push-to-checkout"
  ];

  gitHookDispatch = pkgs.writeShellScript "rex-git-hook" ''
    set -euo pipefail
    name=$(basename "$0")
    repoHook="$(${pkgs.git}/bin/git rev-parse --git-common-dir)/hooks/$name"
    if [ "$name" != pre-push ]; then
      if [ -x "$repoHook" ]; then exec "$repoHook" "$@"; fi
      exit 0
    fi
    input=$(cat)
    while read -r _ localSha _ remoteSha; do
      [[ $localSha =~ ^0+$ ]] && continue
      if [[ $remoteSha =~ ^0+$ ]]; then range="$localSha --not --remotes"; else range="$remoteSha..$localSha"; fi
      ${pkgs.gitleaks}/bin/gitleaks git --no-banner --redact --log-opts="$range" .
    done <<< "$input"
    if [ -x "$repoHook" ]; then exec "$repoHook" "$@" <<< "$input"; fi
  '';

  gitHooks = pkgs.linkFarm "rex-git-hooks"
    (map (name: { inherit name; path = gitHookDispatch; }) gitHookNames);

  gitconfigLocal = pkgs.writeText "rex-gitconfig-local" (lib.generators.toGitINI {
    user = {
      name = "HannesT117-ai";
      email = "350678913+HannesT117-ai@users.noreply.github.com";
    };
    core.hooksPath = "${gitHooks}";
    credential."https://github.com".helper = [ "" "!${pkgs.gh}/bin/gh auth git-credential" ];
    credential."https://gist.github.com".helper = "";
  });

  stateDir = config.users.users.rex.home;
  claudeConfig = ".claude";
  claudeConfigDir = "${stateDir}/${claudeConfig}";
  zshState = ".local/state/zsh";
  persistence = {
    directories = map (directory: { inherit directory; mode = "0700"; }) [
      "servers"
      "uploads"
      claudeConfig
      ".config/gh"
      ".cache"
      zshState
    ];
    files = [ "host-id" ];
  };
  persistedDirs = map (d: "${stateDir}/${d.directory}") persistence.directories;

  zshrcLocal = pkgs.writeText "rex-zshrc-local" ''
    export CLAUDE_CONFIG_DIR=${claudeConfigDir}
    HISTFILE=${stateDir}/${zshState}/history
    [[ $PWD == $HOME ]] && cd ${config.homelab.projects.directory}
  '';

  publicDotfiles = "/etc/dotfiles";
  stowPackage = "shared";

  personalRepoName = "personal";
  personalCheckoutUnit = "${personalRepoName}-checkout";
  personalSyncUnit = "${personalRepoName}-sync";
  personalRepo = config.homelab.git.repos.${personalRepoName}.path;
  personalCheckout = "/run/${personalRepoName}/checkout";
  personalGitCryptKey = "/persist/secrets/${personalRepoName}-git-crypt-key";
in
{
  imports = [ inputs.rex.nixosModules.default ];

  options.homelab.rex.persistence = lib.mkOption {
    type = lib.types.attrs;
    readOnly = true;
    description = ''
      The parts of the rex home (also Rex's state directory) that survive a
      reboot, as impermanence user directories and files. Everything else is
      rebuilt at boot.
    '';
  };

  config = {
    homelab.rex.persistence = persistence;

    services.rex = {
      enable = true;
      extraListen = [ "tailnet://:7297" ];
      logFormat = "json";
      environment.CLAUDE_CONFIG_DIR = claudeConfigDir;
    };

    users.users.rex = {
      shell = pkgs.zsh;
      extraGroups = [ config.homelab.projects.group config.homelab.nixUsers.group ];
      packages = [ pkgs.claude-code pkgs.gh ];
    };

    systemd.services.rex = {
      restartIfChanged = false;
      unitConfig.RequiresMountsFor = [ config.homelab.projects.directory ] ++ persistedDirs;
      serviceConfig = {
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ];
        InaccessiblePaths = config.homelab.sandbox.hiddenPathsFor stateDir;
        ReadWritePaths = [ config.homelab.projects.directory ];
        IPAddressDeny = [
          "localhost"
          "10.0.0.0/8"
          "172.16.0.0/12"
          "192.168.0.0/16"
          "100.64.0.0/10"
          "fe80::/10"
          "fc00::/7"
        ];
        IPAddressAllow = clientAddresses ++ [ "100.100.100.100" ];
        MemoryMax = "4G";
        OOMPolicy = "continue";
        TasksMax = 512;
      };
    };

    homelab.git.repos.${personalRepoName}.requireEncryption = true;

    systemd.services.${personalCheckoutUnit} = {
      description = "Check out and unlock the personal dotfiles for rex";
      wants = [ config.homelab.git.service ];
      after = [ config.homelab.git.service ];
      unitConfig.RequiresMountsFor = [ config.homelab.git.directory ];
      path = [ pkgs.git pkgs.git-crypt pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "git";
        Group = "rex";
        LoadCredential = "git-crypt-key:${personalGitCryptKey}";
        RuntimeDirectory = personalRepoName;
        RuntimeDirectoryMode = "0750";
        UMask = "0027";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateNetwork = true;
        NoNewPrivileges = true;
      };
      script = ''
        git clone --quiet ${personalRepo} ${personalCheckout}
        if ! git -C ${personalCheckout} rev-parse -q --verify HEAD >/dev/null; then
          rm -rf ${personalCheckout}
          exit 0
        fi
        if ! git -C ${personalCheckout} crypt unlock "$CREDENTIALS_DIRECTORY/git-crypt-key"; then
          rm -rf ${personalCheckout}
          exit 1
        fi
        rm -rf ${personalCheckout}/.git
      '';
    };

    systemd.services.rex-dotfiles = {
      description = "Link the public and personal dotfiles into the rex home";
      wantedBy = [ "multi-user.target" "rex.service" ];
      before = [ "rex.service" ];
      wants = [ "${personalCheckoutUnit}.service" ];
      after = [ "${personalCheckoutUnit}.service" ];
      unitConfig.RequiresMountsFor = [ publicDotfiles ] ++ persistedDirs;
      path = [ pkgs.coreutils pkgs.findutils pkgs.stow ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "rex";
        Group = "rex";
        ProtectSystem = "strict";
        ReadWritePaths = [ stateDir ];
        ProtectHome = true;
        PrivateTmp = true;
        PrivateNetwork = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
      };
      script = ''
        dst=${stateDir}
        install -m 0644 ${gitconfigLocal} "$dst/.gitconfig.local"
        install -m 0644 ${zshrcLocal} "$dst/.zshrc.local"

        manifest=${claudeConfigDir}/.rex-dotfiles
        if [ -f "$manifest" ]; then
          while IFS= read -r f; do
            [ -L "$dst/$f" ] || rm -f -- "$dst/$f"
          done < "$manifest"
          rm -f "$manifest"
        fi
        [ -L "$dst/.gitconfig" ] || rm -f "$dst/.gitconfig"

        find "$dst" -path "$dst/.cache" -prune -o -type l -print0 | while IFS= read -r -d "" link; do
          [ -e "$link" ] && continue
          case "$(readlink -m "$link")" in
            ${publicDotfiles}/*|${personalCheckout}/*) rm -f -- "$link" ;;
          esac
        done

        stow --no-folding -d ${publicDotfiles} -t "$dst" --restow ${stowPackage}
        if [ -d ${personalCheckout}/${stowPackage} ]; then
          stow --no-folding -d ${personalCheckout} -t "$dst" --restow ${stowPackage}
        fi
      '';
    };

    systemd.paths.${personalSyncUnit} = {
      wantedBy = [ "paths.target" ];
      pathConfig.PathChanged = [ "${personalRepo}/refs/heads" "${personalRepo}/packed-refs" ];
    };

    systemd.services.${personalSyncUnit} = {
      description = "Re-link the personal dotfiles after a push";
      serviceConfig.Type = "oneshot";
      script = "systemctl restart ${personalCheckoutUnit}.service rex-dotfiles.service";
    };

    networking.firewall.extraInputRules = ''
      iifname "tailscale0" tcp dport 7297 accept
    '';
  };
}
