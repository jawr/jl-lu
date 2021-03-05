---
title: "k8s - a primer"
date: 2021-02-07T10:08:14+09:00
slug: "k8s-a-primer"
description: "kubernetes a primer of what it is and how to use it"
keywords: ["k8s", "devops"]
draft: false
tags: ["k8s", "devops"]
math: false
toc: false
---
## Kubernetes
Much like the film [Primer](https://www.imdb.com/title/tt0390384/), kubernetes
(a ten letter word abbreviated to k8s for reasons) is a complicated tangle of
cleverness that can be quite exasperating, but also very fun.

There is already swathes of content surrounding how kubernetes came about and
how it is useful. I will not add to that mountain. Instead this will be a high
level overview of the main objects I have encountered and how they interact with
each other. 

Some additional arguments have been added to the original
[configs](https://github.com/jawr/whois.bi/blob/master/manifests/postgres.yml)
to show case some kubernetes features.

### Pod
This is the lowest, smallest, but most important object. It wraps a container
that houses your code. In most instances it is a single Docker image.
  	
Although these can be defined separately they are usually defined inside a
`Deployment`. The following `Pod` should be considered a template of a
`Deployment`.

```yaml
# useful for selectors as well as manual kubectl commands
# breaking down your Objects in to multiple labels allows
# more granular control
metadata:
  labels:
	app: postgres
	tier: backend

spec:

  restartPolicy: Always

  # rules that dictate node requirements, i.e. this Pod
  # can only appear on a node with a particular OS, or 
  # hostname
  nodeSelector:
	# ...

  # rules that dictate the pod must avoid matching pods, 
  # nodes, zones
  podAntiAffinity:
  	# ...

  # containers that are run to completion before containers,
  # useful hook that can provide a way to guarantee resource 
  # dependencies 
  initContainers:
  	# ...

  containers:
	- name: postgres
	  # docker image to run
	  image: postgres

	  ports:
		- containerPort: 5432
		  name: postgres

	  volumeMounts:
		- name: postgres-data
		  mountPath: /var/lib/pgsql/data

	  # there are other methods of including env variables, 
	  # but this will map all of our key/values from the 
	  # specified ConfigMap
	  envFrom:
		- configMapRef:
			name: postgres-env


  volumes:
	- name: postgres-data
	  persistentVolumeClaim:
		claimName: postgres-data-claim
```

### Deployment
A description of how many `Pods` of a type are desired and how they are
configured (think resource allotments, failure handling, update handling, etc).
It should also be noted than when declaring a `Deployment`, its definition
includes the `Pod` declaration.

```yaml
apiVersion: apps/v1
kind: Deployment

metadata:
  name: postgres-deploy

spec:
  # define how many pods we want running
  replicas: 1

  # what do we consider to be a replica
  selector:
    matchLabels:
      app: postgres
      tier: backend

  # amount of time newly created pod should be ready without
  # any containers crashing before its considered available
  minReadySeconds: 10

  # amount of time before considered failed
  progressDeadlineSeconds: 600

  # update strategy and additional configuration
  strategy: 
	type: RollingUpdate

  # define the actual pod
  template:

  	# ... see above
```

### Service
Defines an interface to a `Deployment`, i.e. if we had an *API* `Deployment`
that desired 3 replicas/instances, a `Service` would allow other `Deployments`
in the `Cluster` to communicate with the API without having to worry about
IP addresses or DNS.

```yaml
apiVersion: v1
kind: Service

metadata:
  name: postgres
  labels:
    app: postgres
    tier: backend

spec:
  # there are different service types with different options
  # - ClusterIP: is the default and exposes the service to 
  #   all pods in the cluster
  # - NodePort: builds on ClusterIP and allocates a port on 
  #   every node which routes to the clusterIP
  # - LoadBalancer: builds on NodePort and creates an external
  #   load-balancer which routes to the clusterIP
  type: ClusterIP

  # select pods that are considered part of this service
  selector:
    app: postgres
    tier: backend

  # what container ports will be exposed and where
  ports:
    - port: 5432
      targetPort: 5432
      name: postgres
```

### ConfigMap
Provides a way of creating variables/configuration that is needed by different
objects. One use case would be turning them into environment variables used by
`Deployments`.


```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-env
data:
  POSTGRES_USER: whois.bi
  POSTGRES_PASSWORD: ????
  POSTGRES_DB: whois.bi
  POSTGRES_URI: postgres://whois.bi:????@postgres:5432/whois.bi
```

### PersistentStorageClaim
Some `Deployments` will require persistent storage (i.e. a database), as
kubernetes provides reliability by allowing `Pods` to be created and ran on
different `Nodes` there needs to be a mechanism of providing access to this
data. There are plenty of underlying storage classes to choose from, but all
operate through claims (cloud specific offerings, NFS, glusterFS, etc).

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data-claim

spec:
  accessModes:
    # in this instance, the claim is exclusive to One owner
    - ReadWriteOnce

  # what storage class we are making the claim against
  storageClassName: postgres-data

  # describe the minimum resources claimed
  resources:
    requests:
      storage: 1Gi
```

### Ingress
We need a way in which we can provide a load balanced route in to the various
running services. This is available using the `Ingress` Object which is
essentially an nginx instance running.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress
  labels:
    tier: frontend

spec:
  rules:
    - http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api
                port:
                  number: 80

          - path: /adminer
            pathType: Prefix
            backend:
              service:
                name: adminer
                port:
                  number: 8080

          - path: /rabbit
            pathType: Prefix
            backend:
              service:
                name: rabbitmq-manager
                port:
                  number: 15672
```

### Node
A machine (physical, or virtual) that is part of the `Cluster` that runs `Pods`.

### Cluster
A collection of `Nodes` and other Kubernetes services that allow us to run all
these tasty objects.
