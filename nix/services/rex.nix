{ inputs, pkgs, lib, config, ... }:

let
  clientAddresses = [ "100.64.0.1" "fd7a:115c:a1e0::1" ];

  dotfiles = [
    ".zshrc"
    ".claude/AGENTS.md"
    ".claude/agents/architecture-critic.md"
    ".claude/agents/logic-critic.md"
    ".claude/rules/architecture.md"
    ".claude/rules/code-comments.md"
    ".claude/rules/fixing-bugs.md"
    ".claude/rules/handoffs.md"
    ".claude/rules/pr-conventions.md"
    ".claude/rules/skill-routing.md"
    ".claude/skills/retro/SKILL.md"
  ];

  gitconfig = pkgs.writeText "rex-gitconfig" (lib.generators.toGitINI {
    user = {
      name = "HannesT117-ai";
      email = "350678913+HannesT117-ai@users.noreply.github.com";
    };
    init.defaultBranch = "main";
    credential."https://github.com".helper = "!${pkgs.gh}/bin/gh auth git-credential";
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

  dotfilesManifest = pkgs.writeText "rex-dotfiles-manifest" (lib.concatLines dotfiles);
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

    systemd.services.rex-dotfiles = {
      description = "Copy allowlisted dotfiles into the rex account";
      wantedBy = [ "multi-user.target" "rex.service" ];
      before = [ "rex.service" ];
      unitConfig.RequiresMountsFor = [ "/etc/dotfiles" ] ++ persistedDirs;
      path = [ pkgs.coreutils ];
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
        src=/etc/dotfiles/shared
        dst=${stateDir}
        manifest=${claudeConfigDir}/.rex-dotfiles
        if [ -f "$manifest" ]; then
          comm -23 <(sort "$manifest") <(sort ${dotfilesManifest}) | while IFS= read -r f; do
            rm -f -- "$dst/$f"
          done
        fi
        for f in ${lib.escapeShellArgs dotfiles}; do
          if [ ! -f "$src/$f" ]; then
            echo "missing in dotfiles: $f" >&2
            continue
          fi
          install -D -m 0644 "$src/$f" "$dst/$f"
        done
        install -m 0644 ${gitconfig} "$dst/.gitconfig"
        install -m 0644 ${zshrcLocal} "$dst/.zshrc.local"
        install -m 0644 ${dotfilesManifest} "$manifest"
      '';
    };

    networking.firewall.extraInputRules = ''
      iifname "tailscale0" tcp dport 7297 accept
    '';
  };
}
