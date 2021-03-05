---
title: "nixos - starting a kluster"
date: 2021-02-08T23:11:33+09:00
slug: "nixos starting a kubernetes cluster"
description: "using nixops to start a kubernetes cluster"
keywords: ["nixos", "devops", "kubernetes"]
draft: false
tags: ["nixos", "devops", "kubernetes"]
math: false
toc: false
---
## Too many Buzzwords
Lately I have been porting a [project](https://github.com/jawr/whois.bi) from a
systemd service to a fully fledged, cutting edge, Docker on kubernetes
setup.

The main reason for this has been $reason. 

Initially I was using [minikube](https://github.com/kubernetes/minikube) which
uses VirtualBox to create a ready made cluster which is perfect to learn with.

## Searching for a home
After doing some research and deciding that a hosted solution was far too
expensive for my needs, I started to entertain the idea of running my own
cluster and to kubernet all my existing services and projects in to one giant
auto healing, auto scaling ball of cool. 

This was also the perfect opportunity to play with NixOS; having all of
the infrastructure checked in to git and easily extensible and reproducible is a
no brainer, right?

## Cup of tea and plan 
Using [nixops](https://github.com/NixOS/nixops) (*a tool for deploying to NixOS
machines in a network or the cloud*) I would setup a cluster using declarative
configs. 

I would create the following virtual machines running NixOS, each with 2GB ram,
8GB disk and 1VCPU:

- **nixos-fern**, run `nixops` and keep deployment state
- **nixos-node-il**, kubernetes master & node
- **nixos-node-ee**, kubernetes node
- **nixos-node-sam**, kubernetes node

If successful, I would then redeploy the nodes on to Hetzner cloud and proceed
with the assimilation.

### NixOS memory weirdness
The `nix` package manager works in a very different way to others and uses a lot
of memory on some commands causing an OOM, notably when trying to search or
install. 

This was very disconcerting when starting as it made me think I had
done something wrong. It's also going to get worse as more packages are added
(and they have probably the most Pull Requests of any GitHub Repo).
[Details](https://github.com/NixOS/nixpkgs/issues/38635)

## And, Action!
First thing was to install the most basic NixOS instance that would allow an SSH
connection. To keep things simple I ran all the VMs with a Bridged Adapter and
permitted root login, we would also refrain from using a swap as kubernetes does
not like them.

The installation was a manual affair, but incredibly straight forward:

```bash
sudo su

# create partitions and fs
parted /dev/sda -- mklabel msdos
parted /dev/sda -- mkpart primary 1MiB 100%
mkfs.ext4 -L nixos /dev/sda1

# mount and generate basic configuration
mount /dev/sda1 /mnt
nixos-generate-config --root /mnt

# edit /mnt/etc/nixos/configuration.nix
# ensuring that the following are active:
#
# boot.loader.grub.device = "/dev/sda";
# services.openssh.enable = true;
# services.openssh.permitRootLogin = "yes";

nixos-install

reboot
```

Once all the nodes were created, I had to ensure that I had a copy of
`/etc/nixos/hardware-configuration.nix` on `nixos-fern`. This file contained the
disk UUIDs needed for mounting at boot.

The best resource I found for `nixops` documentation and usable examples was
[here](https://releases.nixos.org/nixops/nixops-1.7/manual/manual.html#sec-deploying-to-physical-nixos),
this blog by [Christine Dodtrill](https://christine.website/) has also been an
inspiration. 

My initial dir structure after some failed attempts and trial and
error became:

```linux
kluster/

# root config file, named after a nixops error message
kluster/default.nix

# contains the common/base config used by all nodes
kluster/base.nix

# kubernetes config specifcs were taken from the nixos wiki:
# https://nixos.wiki/wiki/Kubernetes
# configuration specific to the master node
kluster/kubernetes-master.nix
# generic configuration for nodes
kluster/kubernetes-node.nix

# all the aforementioned hardware confis
kluster/node-il/hardware-configuration.nix
kluster/node-ee/hardware-configuration.nix
kluster/node-sam/hardware-configuration.nix
```

This was a very verbose style configuration which had a lot of repetition; it
severely under utilised the Nix language, so I decided to refactor, distil and
spend an inordinate amount of time resetting VMs while I continued to learn more
about the language and `nixops`.

Nixops stores a lot of state inside a SQLite database at `~/.nixops` and when
initially connecting or deploying a machine it creates an SSH Key. As I was
repeatedly deploying bad configs I had to hard reset `nixops` state (read `rm
-rf`). However I did find a very nice SQLite client library in `litecli`.

Eventually I was able to create this config, which allowed me to use a config
file to store state:

```nix
# let allows us to bind some values to names within
# a scope (in: <scope>)
let
  # import a reference to nixpkgs (<> is a special utility
  # that extracts a path from PATH env variable
  pkgs = import <nixpkgs> {};

  # import our state
  metadata = builtins.fromTOML (builtins.readFile ./hosts.toml);

  # create some kubernetes specific variables
  master_ip = metadata.hosts."${metadata.kluster.master}".host;
  master_hostname = metadata.kluster.master;
  master_api = "https://${master_hostname}:443";

  # this is a function that takes a hostname as a parameter and 
  # returns a set (JSON equivilent being an Object)
  kubernetes_master = hostname: {
    roles = ["master" "node"];
    masterAddress = master_hostname;
    easyCerts = true;
    apiserver = {
      securePort = 443;
      advertiseAddress = master_ip;
    };

    addons.dns.enable = true;
    addons.dashboard.enable = true;

    addons.dashboard.rbac.clusterAdmin = true;
    addons.dashboard.extraArgs = [
      "--enable-skip-login"
    ];
  };

  # another function to define node specific settings
  kubernetes_node = hostname: {
	roles = ["node"];
	masterAddress = master_hostname;
	easyCerts = true;

	kubelet.kubeconfig.server = master_api;
	apiserverAddress = master_api;

	addons.dns.enable = true;
  };

  # another utility function; all nodes in this instance
  # were created in VirtualVM and are identical bar their 
  # disk uuid required at mounting
  create_device = uuid: {
	fsType = "ext4";
	device = "/dev/disk/by-uuid/${uuid}";
  };

  # create a function that takes a hostname (... allows it
  # to take and ignore other arguments)
  # this builds our node specific configs by taking specifics
  # defined in our hosts.toml/metadata
  node = { hostname, ... }: {

    # include contents of base.nix where there are even 
    # more generic settings
	imports = [
	  ./base.nix
	];

	networking.hostName = hostname;

    # create a hosts entry for our kubernetes master
    networking.extraHosts = "${master_ip} ${master_hostname}";

    # nixops specific settings, i.e. where to find and what type
    # of machine (i.e. AWS, VirtualBox, GCE)
    deployment.targetHost = metadata.hosts."${hostname}".host;
    deployment.targetEnv = "none";

    # create node specific mount settings
    fileSystems."/" = 
	  create_device metadata.hosts."${hostname}".disk_uuid;

    # set kubernetes packages to be installed, with is another
    # nix keyword that explodes the contents of `pkgs`, it could
    # have also been written as:
    # environment.systemPackages = [ 
	#   pkgs.kubernetes pkgs.kubectl 
	# ];
	environment.systemPackages = with pkgs; [
	  kubernetes
	  kubectl
	];


    # set the services.kubernetes set to contain the value
	# returned by one of the kubernetes_ functions depending 
	# on which host we are looking at
    services.kubernetes = if metadata.kluster.master == hostname
      then kubernetes_master hostname
      else kubernetes_node hostname;
    };
in
{
  # nixops meta data
  network = {
	description = "kubernetes cluster";
	enableRollback = true;
  };

  # create our nodes using the above node function
  il = node { hostname = "il"; };
  ee = node { hostname = "ee"; };
  sam = node { hostname = "sam"; };
}
```

and my `hosts.toml` file looks like:

```toml
[kluster]
master = "il"

[hosts.il]
disk_uuid = "01b3bcba-c0ef-4538-8dd2-f7dee2952322"
host = "192.168.10.121"

[hosts.ee]
disk_uuid = "7278ee48-598d-40fd-9765-a0b0db9ba1d9"
host = "192.168.10.122"

[hosts.sam]
disk_uuid = "f433b748-e485-4668-a7fd-fc5d92fbd682"
host = "192.168.10.123"
```

### Closing thoughts
I don't have much experience with Functional/Lazy/Pure languages (I have
[played](learnyouahaskell.com) with Haskell, but never groked it enough to be
profitable in it) so there has been quite a head wrapping learning curve, but I
do really like the concept of NixOS to pursue it some more.

I have had quite a few issues with `nixops` where it does not feel consistent
and there have been a few times where state has become so off kilter that
resetting VMs manually or `nixops` state has been required. 

There have also been occasions where deployment has failed and rerunning it
succeeds, however in this instance I think it is more an issue with the
`kubernetes` packages than `nixops` itself.

Next steps are to connect them using wireguard leaning heavily on [this blog
post](https://christine.website/blog/my-wireguard-setup-2021-02-06).

When it works as desired it is awesome. *disclaimer, issues caused are almost
definitely mostly caused by me*. 
