{ inputs, pkgs, ... }: {
  imports = [
    inputs.nixos-hardware.nixosModules.common-pc
    inputs.nixos-hardware.nixosModules.common-pc-ssd
    ./hardware-configuration.nix

    # Services
    ../../services/syncthing.nix
  ];

  networking.hostName = "gmktec";
  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Berlin";

  # Boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.editor = false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true; # to support yubikey

  fileSystems."/boot".options = [ "umask=0077" ];

  # User
  users.users.nonroot = {
    isNormalUser = true;
    hashedPassword = "!";
    extraGroups = [ "wheel" ];
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
    settings = {
      PasswordAuthentication = false;
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

  system.stateVersion = "25.11";
}
