---
title: "nixOS - cloud-init"
date: 2021-01-22T12:55:09+09:00
slug: "nixos - cloud-init"
description: "Using cloud init to setup NixOS on scaleway"
keywords: ["nixos", "scaleway"]
draft: false
tags: ["nixos", "scaleway"]
math: false
toc: false
---
## But there's no image?!
When starting a new instance up on [scaleway](https://scaleway.com) there is no
option to select NixOS, but using the [cloud
init](https://nixos.wiki/wiki/Install_NixOS_on_Scaleway_X86_Virtual_Cloud_Server)
hook you are able to boot up an instance. 

After a few moments you can login using your predefined SSH keys which have been
initialised, along with the hostname and SSH serrvice, in `/etc/nixos/configuration.nix`:

```
{ ... }: {
  imports = [
    ./hardware-configuration.nix
    ./host.nix
  ];

  boot.cleanTmpDir = true;
  networking.hostName = "almond";
  networking.firewall.allowPing = true;
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [
    "#" 
    "# WARNING: Automatically generated file" 
    "# This file will be erased at every boot" 
    "# This file was generated with '/usr/local/sbin/scw-fetch-ssh-keys'" 
    "#" 
    "# And recreate your 'authorized_keys' file with the new keys:" 
    "ssh-keys --upgrade'" 
    "#" 
    "ssh-ed25519 ABCDEFG..." 
    "# Below your custom ssh keys from '/root/.ssh/instance_keys'" 
  ];
}
```

## Configuring our install
The main selling point of NixOS is its declarative configuration; you create a
file describing your system and from it you can create a system which is
reproducible. 

For learning I was iterating by modifying `/etc/nixos/host.nix` (the file that
we define in our cloud-init script). After each modification I ran
`nixos-rebuild test`, which attempts to build the new system and "activate" it,
but does not update the bootloader so on a reboot, your current stable system
would be booted. 

After a few iterations I ended up with the following cloud-init file which sets
up the system ready for me to rsync the blog to the server. At a later stage I
plan on using GitHub hooks to automate this stage and have it so everything is
contained in a repo.

```
#cloud-config
write_files:
- path: /etc/nixos/host.nix
  permissions: '0644'
  content: |
    {pkgs, ...}:
    {       
        # create the /var/www directory so we
        # can rsync to it later
        systemd.tmpfiles.rules = [
                "d /var/www/ 755 root root"
        ];
        
        # list of packages we want to install
        environment.systemPackages = with pkgs;
        [       
                neofetch
                vim
                nginx
                rsync
        ];
        
        # allow http/https
        networking.firewall.allowedTCPPorts = [ 80 443 ];
        
        # setup nginx  
        services.nginx = {
                enable = true;
                virtualHosts."jl.lu" = {
                        enableACME = true;
                        forceSSL = true;
                        root = "/var/www/blog";
                
                };
        };
        
        # setup the acme
        security.acme = {
                acceptTerms = true;
                email = "almond-acme@lawrence.pm";
        };
    }

runcmd:
  - curl https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect |  NIXOS_IMPORT=./host.nix NIX_CHANNEL=nixos-20.09 bash 2>&1 | tee /tmp/infect.log
```

