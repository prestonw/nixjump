# NixOS Jump Server Setup

This repository contains the script and configuration to turn a standard Hetzner Ubuntu or Debian cloud server into a clean NixOS jump server. It uses a method called a remote takeover to wipe the existing disk and install a fresh, immutable system over the network.

## How it works

The setup uses nixos-anywhere to handle the hard part of replacing the running operating system. It moves the entire NixOS environment into RAM, partitions the drive, and then reboots into the new system. Once it finishes, the server is managed entirely by a single configuration file.

## Technical breakdown

The system is built on Nix Flakes to keep every software version locked and repeatable. It uses Disko to handle the hard drive partitioning automatically so you do not have to manually format any drives. For networking, it relies on Tailscale to create a private tunnel, and Caddy works as the web proxy to handle site traffic.

## Deployment steps

You need a Tailscale OAuth key before you start. Go to your Tailscale settings and create a client with the devices write scope and the gateway tag. 

Log into your target server as root and run the install script.

curl -L https://raw.githubusercontent.com/prestonw/nixjump/main/install.sh | bash

The script will ask you to paste your Tailscale key. After you provide the key, the script will start the disk wipe and installation. Your SSH connection will drop because the server is being reformatted. Wait about two minutes for the server to reboot and show up in your Tailscale dashboard.

## Files in this repo

The install.sh file is the main script that starts the process. The flake.nix file defines the system versions. The configuration.nix file holds the settings for Tailscale and the Caddy proxy. The disk-config.nix file defines how the 40GB or 80GB cloud disk is sliced up.

## Management

Since this is an immutable system, you do not use apt to install things. If you need to change a setting or update the proxy, you edit the configuration.nix file and run the rebuild command.

nixos-rebuild switch --flake .#jump-server

You can access the server securely without using standard SSH ports by using the tailscale ssh command.

tailscale ssh root@jump-server
