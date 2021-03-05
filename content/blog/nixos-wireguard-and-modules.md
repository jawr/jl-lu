---
title: "nixos - wireguard & modules"
date: 2021-02-16T17:29:58+09:00
slug: "nixos-wireguard-and-modules"
description: "Adding wireguard and refactoring Kluster config to utilise modules instead of functions"
keywords: ["nix", "nixos"]
draft: false
tags: ["nix", "nixos"]
math: false
toc: false
---
## Refactoring
In my [previous post](/blog/nixos-starting-a-kubernetes-cluster/) I attacked the
kubernetes configuration using only one module, the rest created relied on
functions. 

It didn't feel idiomatic and when trying to add wireguard, the cracks
started to appear. It felt like I was fighting with the language.

After some wonderful duck debugging with the excellent community on IRC, I
decided to refactor what I had in to modules.

## Modules
The NixOS [wiki](https://nixos.wiki/wiki/Module) has an excellent article on
modules, but the gist is that a module is a set that has the following syntax:

```nix
{
	imports = [ 
		# paths to other modules that should be included
	];

	options = [
		# define options that can be used to determine the 
		# resulting config
	];

	config = [
		# the processed config that describes your desired 
		# state based on options
	];
}
```

Usually the module is a function: `{ config, pkgs, ... }: {}`. 

There are also variations on the syntax where `options` aren't required and the
returning scope is essentially `config`. 

## Wireguard Module
I wanted the nodes to operate over a wireguard mesh so that I could potentially
run nodes on different networks and guarantee nothing was unintentionally
exposed. 


Our `wireguard.nix` module looks like:

```nix
{ lib, pkgs, config, ... }:
with lib;
let
  # make a shorthand for our config 
  # that is passed in/set by the caller
  cfg = config.role.wireguard;
in {

  # here we define the options we want to 
  # be able to expose to the caller which 
  # help to 
  options.role.wireguard = {
    enable = mkEnableOption "wireguard peer";

    interface = mkOption {
      type = types.str; 
      default = "enp0s3";
    };
 
 	# an option that expects a list of strings
    ips = mkOption { type = types.listOf types.str; };

    privateKey = mkOption { type = types.str; };
    peers = mkOption { type = types.listOf types.attrs; };
  };

  config = mkIf cfg.enable {
    # using cfg, create the actual definition 
    # as described at:
	# https://nixos.wiki/wiki/Wireguard
  };
}
```

When calling the module we are able to set the options (massively simplified to
highlight the module functionality):

```nix
{

    imports = [
      ./wireguard.nix
	  # other imports
    ];
  
  	# set the options that were declared in `wireguard.nix`
    role.wireguard = {
      enable = true;

	  # create a list of ips that this node owns
      ips = pkgs.lib.mapAttrsToList 
		createWireguardIP 
		metadata.hosts."${hostname}".wireguard.ips;

      privateKey = 
	  	metadata.hosts."${hostname}".wireguard.privateKey;

      peers = wireguardPeers;
    };

	# other settings, overrides and option definitions
}
```

### Peers
For each peer you need to make available a list of all peers on the mesh. This
required me to add additional information to the `hosts.toml` file, so that a
node config became:

```toml
[hosts.il]
diskUUID = "01b3bcba-c0ef-4538-8dd2-f7dee2952322"
host = "192.168.10.121"
wireguard.privateKey = "...080EQPtydDdvqJS9+gvIpSDXzaunsKEGY="
wireguard.publicKey = "...nGK6CzvrAImlx9I7u0nybtUtORdgpflFA="
wireguard.ips = { "10.0.0.1" = "32" }
```

*Correctly managing secrets will be an upcoming post.*

To create the peer list we map over the `hosts.toml`.`hosts` set:

```nix
  # create a wireguard ip
  createWireguardIP = ip: cidr: "${ip}/${cidr}";

  # create a wireguard peer (called with key/value)
  createWireguardPeer = hostname: value: {
    publicKey = value.ireguard.publicKey;

	# create a list of ips that this peer owns
    allowedIPs = pkgs.lib.mapAttrsToList 
		createWireguardIP 
		value.wireguard.ips;;

	# endpoint to connect to peer
	endpoint = "${value.host}:51280";
  };

  # build a list of wireguard peers
  wireguardPeers = 
  	pkgs.lib.mapAttrsToList 
		# function to call with the key/value 
		createWireguardPeer 
		# the set to iterate over
		metadata.hosts;
```

## Deploy & Test
To deploy we just run `nixops deploy -d kluster` and once running we can check
the status of wireguard as well as check routing:

```bash
nixops ssh-for-each -d kluster -- wg show
nixops ssh-for-each -d kluster -- ping -c 4 10.0.0.1
```

## Thoughts
For me this method is much easier to reason with than the previous function
heavy approach, I am still able to keep things generic by wrapping it all in a
function: `node = makeNode "hostname"`, but I am able to extract the specifics
out in to their own files.

I would like to improve my `hosts.toml` file so that I can instead define the
options for individual roles in there, making the deployment file even more
generic. 

I'm sure eventually once I'm using machines with varying hardware I
will regret that decision, but for now it makes sense.
