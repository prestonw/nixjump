#!/usr/bin/env bash
set -euo pipefail

# 1. Prerequisites & Key Input
if [[ $EUID -ne 0 ]]; then echo "Run as root"; exit 1; fi

echo "Go to: https://login.tailscale.com/admin/settings/oauth"
echo "Generate a client with 'devices:write' scope and 'tag:gateway'."
read -rsp "Paste Tailscale Key: " TS_KEY
echo -e "\nKey received. Starting deployment..."

# 2. Environment Setup
export NIX_CONFIG="experimental-features = nix-command flakes"
if ! command -v nix &> /dev/null; then
    curl -L https://nixos.org/nix/install | sh -s -- --daemon
    source /etc/profile.d/nix.sh
fi

# 3. Build Configuration
mkdir -p /tmp/nixos-install && cd /tmp/nixos-install

printf '{
  disko.devices.disk.main = {
    device = "/dev/sda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        boot = { size = "1M"; type = "EF02"; };
        ESP = { size = "512M"; type = "EF00"; content = { type = "filesystem"; format = "vfat"; mountpoint = "/boot"; }; };
        root = { size = "100%%"; content = { type = "filesystem"; format = "ext4"; mountpoint = "/"; }; };
      };
    };
  };
}' > disk-config.nix

printf '{ modulesPath, pkgs, ... }: {
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ./disk-config.nix ];
  boot.loader.grub = { enable = true; device = "/dev/sda"; };
  networking.hostName = "jump-server";
  services.tailscale.enable = true;
  services.tailscale.useRoutingFeatures = "server";

  systemd.services.tailscale-autoconnect = {
    after = [ "network-pre.target" "tailscale.service" ];
    wants = [ "network-pre.target" "tailscale.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = "${pkgs.tailscale}/bin/tailscale up --authkey=%s --ssh --ephemeral";
  };

  services.caddy = {
    enable = true;
    virtualHosts."*" = {
      extraConfig = "reverse_proxy 100.x.y.z:443";
    };
  };

  environment.systemPackages = with pkgs; [ vim wget curl git htop jq ];
  system.stateVersion = "24.11";
}' "$TS_KEY" > configuration.nix

printf '{
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
}' > flake.nix

# 4. Execution
nix run github:nix-community/nixos-anywhere -- --flake .#jump-server localhost
