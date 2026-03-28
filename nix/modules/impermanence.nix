{ pkgs, lib, ... }:

let
  rollbackScript = pkgs.writeShellScript "rollback-root" ''
    set -euo pipefail

    BTRFS_TOP=/tmp/btrfs-rollback
    mkdir -p "$BTRFS_TOP"
    mount -t btrfs -o subvolid=5 /dev/mapper/cryptroot "$BTRFS_TOP"

    # Delete any nested subvolumes systemd may have created under @
    btrfs subvolume list -o "$BTRFS_TOP/@" 2>/dev/null \
      | while read -r line; do
          sub="''${line##* }"
          btrfs subvolume delete "$BTRFS_TOP/$sub" || true
        done

    # Swap: delete current @ and restore from blank snapshot
    btrfs subvolume delete "$BTRFS_TOP/@"
    btrfs subvolume snapshot "$BTRFS_TOP/@blank" "$BTRFS_TOP/@"

    umount "$BTRFS_TOP"
  '';
in
{
  # disko owns the fileSystems definitions for /persist and /var/log.
  # impermanence requires neededForBoot = true on both — set here via merge.
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/var/log".neededForBoot = true;

  # Wipe / on every boot by rolling back @ to the empty @blank snapshot.
  # Must run after LUKS unlock but before sysroot.mount.
  # boot.initrd.postDeviceCommands is NOT available with systemd initrd — use a service instead.
  boot.initrd.systemd.services.rollback-root = {
    description = "Rollback btrfs root to blank snapshot";
    wantedBy = [ "initrd.target" ];
    after = [ "cryptsetup.target" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = rollbackScript;
    };
  };

  # Both the rollback script and btrfs-progs must be in the initrd
  boot.initrd.systemd.storePaths = [ rollbackScript pkgs.btrfs-progs ];

  # Persistent state declarations — everything listed here is bind-mounted from /persist
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      # System identity
      "/var/lib/nixos"

      # Secure Boot PKI — loss requires re-creating keys and re-enrolling in UEFI
      "/var/lib/sbctl"

      # Services
      "/var/lib/caddy"       # Loss of TLS certificates triggers re-issuance (rate limited)
      "/var/lib/syncthing"
      "/var/lib/paperless"
      "/var/lib/tailscale"
      "/var/lib/fail2ban"

      # Network
      { directory = "/etc/NetworkManager/system-connections"; mode = "0700"; }
      "/var/lib/NetworkManager"

      # NixOS flake repository
      "/etc/nixos"

      # Avoid re-cloning dotfiles from GitHub on every boot
      "/etc/dotfiles"
    ];
    files = [
      # Machine identity — stable across boots for journalctl, dbus, etc.
      "/etc/machine-id"

      # SSH host key — if this changes, all clients reject the server (hard lockout)
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
  };

  # Enforce permissions on secrets directory
  systemd.tmpfiles.rules = [
    "d /persist/secrets 0700 root root -"
  ];

  # sudo lecture file lives on ephemeral root — suppress it instead of persisting
  security.sudo.extraConfig = "Defaults lecture = never";
}
