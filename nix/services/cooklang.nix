{ config, pkgs, lib, ... }:

let
  version = "0.27.1";

  cookcli = pkgs.stdenv.mkDerivation {
    pname = "cookcli";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/cooklang/cookcli/releases/download/v${version}/cook-x86_64-unknown-linux-musl.tar.gz";
      hash = "sha256-2pGY0JfKL7ddzNqBmRm4dNKgaaIuU1Z4BVIn7JZ4/QE=";
    };

    sourceRoot = ".";
    dontBuild = true;

    installPhase = ''
      mkdir -p $out/bin
      install -m755 cook $out/bin/cook
    '';
  };

  recipesDir = "/var/lib/syncthing/obsidian/main/rezepte";
in {

  # Syncthing group grants read access to recipes
  users.users.cooklang = {
    isSystemUser = true;
    group = "syncthing";
  };

  # Ensure recipes directory exists with syncthing ownership
  systemd.tmpfiles.rules = [
    "d ${recipesDir} 0750 syncthing syncthing -"
  ];

  # CookLang recipe server
  systemd.services.cooklang = {
    description = "CookLang Recipe Server";
    after = [ "network.target" "syncthing.service" ];
    wants = [ "syncthing.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "cooklang";
      Group = "syncthing";
      ExecStart = "${cookcli}/bin/cook server ${recipesDir} --host --port 9080";
      Restart = "always";
      RestartSec = 10;

      # Systemd hardening
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      RestrictNamespaces = true;
      RestrictRealtime = true;
      LockPersonality = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      SystemCallArchitectures = "native";
    };
  };

  # Firewall (Tailscale)
  networking.firewall.extraInputRules = ''
    ip saddr 100.64.0.0/24 tcp dport 9080 accept
  '';
}
