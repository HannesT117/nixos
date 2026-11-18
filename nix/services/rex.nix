{ inputs, pkgs, lib, config, ... }:

let
  clientAddresses = [ "100.64.0.1" "fd7a:115c:a1e0::1" ];

  claudeConfigFiles = [
    "AGENTS.md"
    "agents/architecture-critic.md"
    "agents/logic-critic.md"
    "rules/architecture.md"
    "rules/code-comments.md"
    "rules/fixing-bugs.md"
    "rules/handoffs.md"
    "rules/pr-conventions.md"
    "rules/skill-routing.md"
    "skills/retro/SKILL.md"
  ];
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

  systemd.services.rex-claude-config = {
    description = "Copy allowlisted Claude config from dotfiles into the rex account";
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
      src=/etc/dotfiles/shared/.claude
      dst=/var/lib/rex/.claude
      for f in ${lib.escapeShellArgs claudeConfigFiles}; do
        if [ ! -f "$src/$f" ]; then
          echo "missing in dotfiles: $f" >&2
          continue
        fi
        install -D -m 0644 "$src/$f" "$dst/$f"
      done
    '';
  };

  networking.firewall.extraInputRules = ''
    iifname "tailscale0" tcp dport 7297 accept
  '';
}
