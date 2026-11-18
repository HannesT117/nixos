{ config, pkgs, lib, ... }:

let
  port = "2719";
  app = ../../apps/planner;
  python = pkgs.python3.withPackages (ps: [ ps.marimo ps.polars ]);
  backupDir = "/var/lib/syncthing/planner-backup";
in
{
  users.users.planner = {
    isSystemUser = true;
    group = "planner";
    home = "/var/lib/planner";
  };
  users.groups.planner = {};

  systemd.services.planner = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    environment = {
      PLANNER_DB = "/var/lib/planner/planner.sqlite";
      HOME = "/var/lib/planner";
      XDG_CONFIG_HOME = "/var/lib/planner/.config";
      XDG_CACHE_HOME = "/var/lib/planner/.cache";
    };
    serviceConfig = {
      ExecStart = "${python}/bin/marimo run ${app}/planner.py --headless --host 127.0.0.1 --port ${port}";
      WorkingDirectory = app;
      User = "planner";
      Group = "planner";
      StateDirectory = "planner";
      StateDirectoryMode = "0700";
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
      InaccessiblePaths = config.homelab.sandbox.hiddenPathsFor "/var/lib/planner";
      MemoryMax = "4G";
      OOMPolicy = "continue";
      TasksMax = 512;
    };
  };

  services.caddy.virtualHosts."money.jrdn.cx".extraConfig = ''
    forward_auth localhost:9091 {
      uri /api/authz/forward-auth
      copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
    }
    reverse_proxy localhost:${port}
  '';

  networking.nftables.tables.planner-local = {
    family = "inet";
    content = ''
      chain output {
        type filter hook output priority filter; policy accept;
        oifname "lo" tcp dport ${port} ct state new ${config.homelab.caddy.onlyCaddy} reject with tcp reset
      }
    '';
  };

  systemd.services.planner-backup = {
    description = "Back up the planner database to syncthing";
    path = [ pkgs.sqlite pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    script = ''
      umask 077
      DB=/var/lib/planner/planner.sqlite
      BACKUP_DIR=${backupDir}
      [ -s "$DB" ] || { echo "$DB missing or empty" >&2; exit 1; }
      mkdir -p "$BACKUP_DIR"
      rm -f "$BACKUP_DIR"/*.sqlite.tmp
      TARGET="$BACKUP_DIR/$(date -u +%Y-%m-%dT%H-%M-%SZ).sqlite"
      sqlite3 -readonly "$DB" ".backup '$TARGET.tmp'"
      mv "$TARGET.tmp" "$TARGET"
      ls -1 "$BACKUP_DIR"/*.sqlite | sort -r | tail -n +31 | xargs -r rm --
      chown -R syncthing:syncthing "$BACKUP_DIR"
    '';
  };

  systemd.timers.planner-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
