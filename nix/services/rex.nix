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
  });
in
{
  imports = [ inputs.rex.nixosModules.default ];

  services.rex = {
    enable = true;
    extraListen = [ "tailnet://:7297" ];
    logFormat = "json";
  };

  users.users.rex = {
    shell = pkgs.zsh;
    packages = [ pkgs.claude-code ];
  };

  systemd.services.rex = {
    restartIfChanged = false;
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
      InaccessiblePaths = config.homelab.sandbox.hiddenPathsFor "/var/lib/rex";
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
    unitConfig.RequiresMountsFor = [ "/etc/dotfiles" "/var/lib/rex" ];
    path = [ pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "rex";
      Group = "rex";
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/lib/rex" ];
      ProtectHome = true;
      PrivateTmp = true;
      PrivateNetwork = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
    };
    script = ''
      src=/etc/dotfiles/shared
      dst=/var/lib/rex
      for f in ${lib.escapeShellArgs dotfiles}; do
        if [ ! -f "$src/$f" ]; then
          echo "missing in dotfiles: $f" >&2
          continue
        fi
        install -D -m 0644 "$src/$f" "$dst/$f"
      done
      install -m 0644 ${gitconfig} "$dst/.gitconfig"
    '';
  };

  networking.firewall.extraInputRules = ''
    iifname "tailscale0" tcp dport 7297 accept
  '';
}
