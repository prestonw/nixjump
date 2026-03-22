#!/usr/bin/env bash
set -e

# 1. Install Nix on Ubuntu (Standalone)
if ! command -v nix &> /dev/null; then
    echo "Installing Nix..."
    curl -L https://nixos.org/nix/install | sh -s -- --daemon
    . /etc/profile.d/nix.sh
fi

# 2. Create the Declarative Config Files
cat <<EOF > disk-config.nix
{
  disko.devices = {
    disk = {
      main = {
        device = "/dev/sda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            boot = { size = "1M"; type = "EF02"; };
            ESP = {
              size = "512M";
              type = "EF00";
              content = { type = "filesystem"; format = "vfat"; mountpoint = "/boot"; };
            };
            root = {
              size = "100%";
              content = { type = "filesystem"; format = "ext4"; mountpoint = "/"; };
            };
          };
        };
      };
    };
  };
}
EOF

cat <<EOF > configuration.nix
{ modulesPath, config, lib, pkgs, ... }: {
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ./disk-config.nix ];
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";

  networking.hostName = "jump-server";
  services.openssh.enable = true;
  services.tailscale.enable = true;
  services.caddy = {
    enable = true;
    virtualHosts."*" = {
      extraConfig = "reverse_proxy localhost:8080"; # Placeholder
    };
  };

  # Replace this with your actual public key from your iMac
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..." 
  ];

  environment.systemPackages = with pkgs; [ vim wget curl git htop ];
  system.stateVersion = "24.11";
}
EOF

cat <<EOF > flake.nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { nixpkgs, disko, ... }: {
    nixosConfigurations.jump-server = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ disko.nixosModules.disko ./configuration.nix ];
    };
  };
}
EOF

# 3. Trigger the Takeover
echo "Starting NixOS Takeover... This will disconnect your SSH session."
nix run github:nix-community/nixos-anywhere -- --flake .#jump-server localhost
