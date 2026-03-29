{ inputs, pkgs, lib, ... }: {
  imports = [
    inputs.lanzaboote.nixosModules.lanzaboote
    inputs.impermanence.nixosModules.impermanence
    inputs.disko.nixosModules.disko
    inputs.nixos-hardware.nixosModules.common-pc
    inputs.nixos-hardware.nixosModules.common-pc-ssd
    ./hardware-configuration.nix
    ./disko.nix

    # Services
    ../../services/syncthing.nix
    ../../services/tailscale.nix
    ../../services/paperless.nix
    ../../services/cooklang.nix
    ../../services/reverse-proxy.nix
  ];

  networking.hostName = "gmktec";
  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Berlin";

  # Boot
  boot.loader.systemd-boot.enable = lib.mkForce false; # Prevent nixOS from installing unsiged EFI binaries
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;
  boot.initrd.kernelModules = [ "tpm_crb" ];

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };

  # LUKS: try TPM2 first, then FIDO2, fall back to passphrase
  boot.initrd.luks.devices."cryptroot".crypttabExtraOpts = [
    "tpm2-device=auto"
    "fido2-device=auto"
    "token-timeout=60"
  ];

  # Set passwords from files on every boot
  users.mutableUsers = false;
  users.users.root.hashedPasswordFile = "/persist/secrets/root-password-hash";
  # Change password: mkpasswd -m yescrypt | sudo tee /persist/secrets/root-password-hash

  users.users.nonroot = {
    isNormalUser = true;
    hashedPassword = "!"; # No password for nonroot. Only ssh possible.
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAWETf+yIYzRkaPHjcoHgF2mW2lD7XXJbqPhfUeLrXbg MacBookAir"
    ];
    packages = with pkgs; [
      tree
    ];
  };


  # SSH
  services.openssh = {
    enable = true;
    ports = [ 8822 ];
    hostKeys = [
      { path = "/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; }
    ];
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      X11Forwarding = false;
      AllowUsers = [ "nonroot" ];
    };
  };

  # Firewall
  networking.firewall.allowedTCPPorts = [ 8822 ];

  # Intrusion prevention
  services.fail2ban = {
    enable = true;
    bantime = "31d";
    bantime-increment.enable = true;
  };

  environment.systemPackages = with pkgs; [
    sbctl
  ];

  system.stateVersion = "25.11";
}
