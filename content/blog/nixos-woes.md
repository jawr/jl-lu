---
title: "nixos & kubernete woes"
date: 2021-03-04T09:49:21+09:00
slug: "nixos and kubernetes woes"
description: "An overview of issues encountered when setting up kubernetes over
wireguard on k3s"
keywords: ["k3s", "nixos", "longhorn", "routing"]
draft: false
tags: ["k3s", "nixos", "longhorn", "routing"]
math: false
toc: false
---
After my recent fiddling with k8s, I decided to try out k3s which offers a
slimmed down version of kubernetes. I also decided to take the plunge and push
up my virtual experimenting and place it in to the cloud, using the lovely
[Hetzner nixops plugin](https://github.com/lukebfox/nixops-hetznercloud).

## Routing Hell
By far the most frustrating issue I encountered revolved around routing. Inter
communication between the nodes is unencrypted by default (when using flannel)
and so I wanted to link all nodes and pod via wireguard. 

On my initial attempts with kubernetes over wireguard I had some false positives
so I didn't realise the issues until later when introducing larger systems into
the cluster. 

The issue was that pods could route to other pods on the same network, but not
inter node. Nodes could route to other nodes. So somewhere in the flannel they
were being dropped.

After much debugging, sweat and tears I was able to discover that wireguard
attempts to create routes based on it's `AllowedIPs` configuration. Flannel was
then seeing some routes that were broader than the ones it wanted to apply, and
didn't apply them. 


#### Routing recap.

```
<cidr to match> via <gateway> dev <iface> ... src <return to>
```

The correct routing table for two nodes looks like so:

```
# defalut route out in to the WAN
peach> default via 172.31.1.1 dev ens3 proto dhcp src 157.90.166.85 metric 202

# default route for wireguard traffic, make sure to add the source so it can
# be routed back
peach> 10.0.0.0/24 dev wg0 proto kernel scope link src 10.0.0.2

# flannel subnets, each one belongs to a different node
peach> 10.42.0.0/24 via 10.0.0.1 dev wg0
peach> 10.42.1.0/24 via 10.0.0.3 dev wg0

# peach's flannel subnet should gateway to cni0 device
peach> 10.42.2.0/24 dev cni0 proto kernel scope link src 10.42.2.1

# an example of a container running on the machine, sits behind cni0
peach> 169.254.0.0/16 dev vethc088db56 scope link src 169.254.234.223 metric 205
```

```
plum.> default via 172.31.1.1 dev ens3 proto dhcp src 116.203.149.40 metric 202
plum.> 10.0.0.0/24 dev wg0 proto kernel scope link src 10.0.0.1
plum.> 10.42.0.0/24 dev cni0 proto kernel scope link src 10.42.0.1
plum.> 10.42.1.0/24 via 10.0.0.3 dev wg0
plum.> 10.42.2.0/24 via 10.0.0.2 dev wg0
plum.> 169.254.0.0/16 dev veth8a894736 scope link src 169.254.137.223 metric 205
```

This can be pictured as:

```
     ~node plum~                ~node peach~
     +-----------------+        +-----------------+
     | container/vethN |        | container/vethN |
     | 169.254.0.0/16  |        | 169.254.0.0/16  |
     +-----------------+        +-----------------+     
         ^                           ^
         |                           |
         v                           V
     +--------------+           +--------------+
     | flannel/cni0 |           | flannel/cni0 |
     | 10.42.0.0/16 | <=======> | 10.42.2.0/16 |
     +--------------+           +--------------+
         ^                           ^
         |                           |
         v                           V
     +---------------+          +---------------+
     | wireguard/wg0 |          | wireguard/wg0 |
     | 10.0.0.1/24   | <======> | 10.0.0.2/24   |
     +---------------+          +---------------+
         ^                           ^
         |                           |
         v                           v
     +---------------+          +---------------+
     | internet/ens3 | <------> | internet/ens3 |
     +---------------+          +---------------+

     <----> actual traffic flow
     <====> virtual traffic flow
```

As you can see traffic can flow virtually at the flannel and wireguard levels,
but in actual fact traverses the internet. Flannel is responsible for keeping
state of which veth/container belongs to which IP on the flannel network. 

At each level there is a degree of encapsulation and it is very important that
during the routing that a `src` is correctly declared to allow for return
routing.

#### Nix configuration notes
In order to get this written declaratively we need to provide each node with a
flannel config that predefines the subnet configuration. Allowing us to
preconfigure the correct `AllowedIPS`.

This file can be found at `/run/flannel/subnet.env`:

```
peach> FLANNEL_NETWORK=10.42.0.0/16
peach> FLANNEL_SUBNET=10.42.2.1/24
peach> FLANNEL_MTU=1420
peach> FLANNEL_IPMASQ=true
```

## Persistent Storage
One very important system that I needed to introduce early on in to the cluster
was a way in which I could persist data. For dev and experimental clusters that
do not require redundancy using local node storage is fine. 

The main reason I wanted to avoid that was it meant that deployments had to be
tied to nodes to have persistent storage, something I felt was completely
against the entire of kubernetes. 


I tried the following storage systems, but eventually settled on longhorn which
was easiest to setup.

- [longhorn](https://longhorn.io/)
- [rook](https://rook.io/)
- [Portworx](https://portworx.com/)

#### Docker Images
The images provided by longhorn do not inherit the PATH variable which is the
underbelly of NixOS. Digging through issues I was able to find the following
repo which addresses some PATH issues, the Docker file is essentially a wrapper
and is exceptionally simple:

```
FROM docker.io/longhornio/longhorn-manager:v1.1.0
ENV PATH="${PATH}:/run/wrappers/bin:/run/current-system/sw/bin"
```

Related [issue](https://github.com/longhorn/longhorn/issues/2166)

#### LVM
This is a required dependency for longhorn. Unfortunately it has explicitly set
the paths to check when looking for `lvm`:

The current (temporary) solution:

```
mkdir /sbin && cd /sbin && ln -s /run/current-system/sw/bin/lvm lvm
```

The long term solution would be to fix the code base to correctly search the
host PATH. 


#### ISCSI
Package from NixOS is very bare bones and doesn't provide you with a basic
environment, this caused some very obscure issues that were hard to track down
(a reoccurring theme with distributed systems on kubernetes). 

Some examples I found were red herrings.

```
I0303 11:06:24.559878       1 main.go:91] Version: v2.2.1-lh1-0-gda3ee62d
I0303 11:06:37.901356       1 connection.go:153] Connecting to unix:///csi/csi.sock
I0303 11:06:41.348742       1 common.go:111] Probing CSI driver for readiness
I0303 11:06:41.349005       1 connection.go:182] GRPC call: /csi.v1.Identity/Probe
I0303 11:06:41.349096       1 connection.go:183] GRPC request: {}
I0303 11:06:53.673409       1 connection.go:185] GRPC response: {}
I0303 11:06:56.622624       1 connection.go:186] GRPC error: <nil>
I0303 11:06:56.622953       1 connection.go:182] GRPC call: /csi.v1.Identity/GetPluginInfo
I0303 11:06:56.623048       1 connection.go:183] GRPC request: {}
I0303 11:06:58.996617       1 connection.go:185] GRPC response: {}
I0303 11:07:02.400033       1 connection.go:186] GRPC error: rpc error: code = DeadlineExceeded desc = context deadline exceeded
E0303 11:07:02.400801       1 main.go:133] rpc error: code = DeadlineExceeded desc = context deadline exceeded
```

In one of the nodes I was able to spot this error which led me to a solution:
```
Mar 03 10:08:19 plum iscsid-start[617]: iscsid: Warning: InitiatorName file /etc/iscsi/initiatorname.iscsi does not exist or does not contain a properly formatted InitiatorName. If using software iscsi (iscsi_tcp or ib_iser) or partial offload (bnx2i or cxgbi iscsi), you may not be able to log into or discover targets. Please create a file /etc/iscsi/initiatorname.iscsi that contains a sting with the format: InitiatorName=iqn.yyyy-mm.<reversed domain name>[:identifier].
```

Create an identifier on every machine:

```
iscsi-iname -p "InitiatorName=iqn.2005-03.org.open-iscsi" > /etc/iscsi/initiatorname.iscsi
```
