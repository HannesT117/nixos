{
  description = "GMKTec homelab";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:nixos/nixos-hardware";
  };

  outputs = { self, nixpkgs, nixos-hardware, ... } @ inputs: {
    nixosConfigurations.gmktec = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./nix/modules # import modules by path rather than flake outputs as long as there's only 1 host
        ./nix/hosts/gmktec
      ];
      specialArgs = { inherit inputs; };
    };
  };
}
