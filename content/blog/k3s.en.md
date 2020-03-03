---
Title: k3s, k8s minus 5 !
Date: 2020-03-02
Category: Kubernetes
Summary: Rancher k3s is a Kubernetes distribution, ligthweight, packaged into a 50MB binary file ready to be used for your CI jobs
Author: Romain Guichard
image: images/thumbnails/k3s.png
lang: en
---

K3s is a product from [Rancher](https://rancher.com/), your know them for their
eponym product [Rancher](https://rancher.com/products/rancher/) as well for
others products like [RKE](https://rancher.com/docs/rke/latest/en/) or
[Rio](https://rio.io).

K3s is a lightweight  Kubernetes distribution. Especially designed for IoT,
Edge Computing or CI/CD environments. K3s is packaged into a 50MB binary file
and can be deployed faster than you can imagine.

### Why is that interesting ?

As time goes by, Kubernetes is becoming the _de facto_ platform to deploy and
run your applications. It's not just the x86 world, you could, with good
reason, want to deploy a Kubernetes cluster elsewhere. Indeed, some IT systems
don't have the power to run a multi-master cluster, some need to be spin up as
fast as they would need to be spin down. But all these systems have one thing
in common, the need the Kubernetes API. So yes, k3s is not for production, not
a typical IT production with x86 servers in a standard environment. But for
Edge Computing or CI jobs, it's a perfect match.

Obviously, some parts of Kubernetes are missing or have changed :

- "legacy" or "alpha" features have been removed
- SQLite3 replaces ETCD by default
- addons are disabled

But inside, the pretty much the same thing.

![archi_k8s](https://k3s.io/images/how-it-works-k3s.svg#center)

Two things to keep in mind :

- containerd is the container runtime, no Docker here
- flannel is the pod network addon

### Déploiement

Let's get the [latest release on
GitHub](https://github.com/rancher/k3s/releases/latest) and then :

```
# ./k3s server
INFO[2020-01-13T17:13:58.476545083+01:00] Starting k3s v1.17.0+k3s.1 (0f644650)
[...]
# ./k3s kubectl get node
NAME           STATUS   ROLES    AGE   VERSION
rguichard-x1   Ready    master   59s   v1.17.0+k3s.1
```

39 seconds. 39 seconds to spin up a single master Kubernetes cluster. As I
said, faster than you could imagine. Since the v1.0.0, k3s supports [a
multi-master mode as an experimental
feature]((https://rancher.com/docs/k3s/latest/en/installation/ha-embedded/).

K3s includes also :

- Traefik as the Ingress Controller
- Manifests auto-deployment
- Helm v3


### Kubernetes in Docker

What's really interested is that you could easily run k3s inside a Docker
container. Rancher provides another tool to help us deployd k3s insise a Docker
container : [k3d](https://github.com/rancher/k3d).

```
# k3d create
k3d create
INFO[0000] Created cluster network with ID 78aa4d1f42d61f04314c89c0c2e93f49267ba995746a9e1734bad57c099d2c76
INFO[0000] Created docker volume  k3d-k3s-default-images
INFO[0000] Creating cluster [k3s-default]
INFO[0000] Creating server using docker.io/rancher/k3s:v1.17.2-k3s1...
INFO[0000] Pulling image docker.io/rancher/k3s:v1.17.2-k3s1...
INFO[0007] SUCCESS: created cluster [k3s-default]
INFO[0007] You can now use the cluster with:

export KUBECONFIG="$(k3d get-kubeconfig --name='k3s-default')"
kubectl cluster-info
# export KUBECONFIG="$(k3d get-kubeconfig --name='k3s-default')"
# kubectl get node
NAME                     STATUS   ROLES    AGE   VERSION
k3d-k3s-default-server   Ready    master   14s   v1.17.2+k3s1
```

It works well, maybe even faster.

### k3s in Travis-CI

For some years, most of CI providers (travis-ci, circle-ci, concourse etc)
can provide a Docker environment for running your jobs inside containers. They
provide the Docker daemon, you provide the images. There are many pros doing
that, fixed dependancies, provider agnosticity, close production and tests
environments etc.

But as I said earlier, Kubernetes is the _de facto_ platform, not Docker. You
want to tests your new images and their execution by [Docker or another
container runtime](https://particule.io/blog/container-runtime/) as well
as your Kubernetes resources : Deployment, Service, StatfullSets, DaemonSets
etc.

We are going to use k3s to deploy a Kubernetes environment inside a Travis-CI
project.

```
$ cat .travis-ci.yml
branches:
  only:
  - master
services:
  - docker
before_install:
  - wget https://storage.googleapis.com/kubernetes-release/release/v1.17.0/bin/linux/amd64/kubectl
  - wget https://github.com/rancher/k3d/releases/download/v1.6.0/k3d-linux-amd64
  - chmod +x k3d-linux-amd64 kubectl
  - sudo mv k3d-linux-amd64 /usr/local/bin/k3d
  - sudo mv kubectl /usr/local/bin
  - k3d --version
script:
  - k3d create
  - sleep 15
  - export KUBECONFIG="$(k3d get-kubeconfig --name='k3s-default')"
  - kubectl get node
```

Everything went as expected. In a few dozens of seconds, we have a Kubernetes
cluster in which we can run any tests on any applications we want, the same way we
would do on a kubeadm Kubernetes cluster.

[Romain Guichard](https://www.linkedin.com/in/romainguichard/), CEO &
Co-founder
