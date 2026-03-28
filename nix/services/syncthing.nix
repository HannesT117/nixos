{ config, pkgs, ... }: {

  # Syncthing - file synchronisation
  services.syncthing = {
    enable = true;
    user = "syncthing";
    group = "syncthing";
    dataDir = "/var/lib/syncthing";
    configDir = "/var/lib/syncthing/.config/syncthing";

    # Web UI only on localhost
    guiAddress = "0.0.0.0:8384";

    openDefaultPorts = true; # TCP 22000 + UDP 22000 for sync, UDP 21027 for discovery
  };

  # Firewall
  networking.firewall.extraInputRules = ''
    ip saddr 100.64.0.0/24 tcp dport 8384 accept
  '';

  # Systemd hardening — sandbox the service
  systemd.services.syncthing.serviceConfig = {
    # Filesystem isolation
    ProtectSystem = "strict";           # read-only access to /usr, /boot, /etc
    ProtectHome = true;                 # no access to /home
    PrivateTmp = true;                  # isolated /tmp
    ReadWritePaths = [ "/var/lib/syncthing" ];  # only its own data dir is writable

    # Privilege restrictions
    NoNewPrivileges = true;             # can't escalate privileges
    PrivateDevices = true;              # no access to physical devices
    ProtectKernelTunables = true;       # no writing to /proc or /sys
    ProtectKernelModules = true;        # can't load kernel modules
    ProtectKernelLogs = true;           # no access to kernel log
    ProtectControlGroups = true;        # no access to cgroups
    RestrictNamespaces = true;          # can't create new namespaces
    RestrictRealtime = true;            # no realtime scheduling
    MemoryDenyWriteExecute = true;      # no writable+executable memory
    LockPersonality = true;             # can't change execution domain

    # Network restrictions — only what syncthing needs
    RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" ];

    # System call filtering
    SystemCallArchitectures = "native";
  };
}
