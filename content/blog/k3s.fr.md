---
Title: k3s, k8s moins 5 !
Date: 2020-03-02
Category: Kubernetes
Summary: Rancher k3s est une distribution Kubernetes, légère, dans un binaire de 50Mo prêt à l'emploi pour vos jobs de CI
Author: Romain Guichard
image: images/thumbnails/k3s.png
lang: fr
---

K3s est un produit de chez [Rancher](https://rancher.com/), on les connait
notamment pour leur produit éponyme
[Rancher](https://rancher.com/products/rancher/) ainsi que pour d'autres
produits comme [RKE](https://rancher.com/docs/rke/latest/en/) ou
[Rio](https://rio.io).

K3s est distribution Kubernetes légère. Particulièrement adaptée pour l'IoT, le edge computing ou bien les
environements de CI/CD. En effet, k3s tient dans un binaire d'à peine 50Mo et
peut donc être déployée extrêmement rapidement.

### Pourquoi c'est bien ?

Au fur et à mesure que Kubernetes devient _de facto_ la plateforme pour faire
tourner vos applications, l'envie se fait grande de la déployer autre part que
seulement sur des serveurs x86 classiques. Certains systèmes n'ont pas la
capacité de faire tourner 3 masters/X nodes ou bien nécessitent d'être déployé/détruit
extrêmement rapidement mais ont besoin d'une chose, l'API de Kubernetes. Non
k3s n'est pas orienté production, en tout cas pas de la production classique sur
des serveurs classiques dans un environnement classique. Le edge-computing, les
jobs de CI semblent être de parfaits candidats.

En contrepartie, certaines fonctions ne sont pas disponibles :

- les fonctionnalités "legacy" ou "alpha" sont supprimées
- SQLite3 remplace etcd par défaut
- les addons sont désactivés

Mais sur le fonctionnement interne, on retrouve quelque chose d'approchant un
cluster Kubernetes traditionnel.

![archi_k8s](https://k3s.io/images/how-it-works-k3s.svg#center)

On notera que :

- containerd est la container runtime utilisée
- flannel est le pod network addon utilisé

### Déploiement

On récupère tout d'abord [la dernière release sur
GitHub](https://github.com/rancher/k3s/releases/latest) puis :

```
# ./k3s server
INFO[2020-01-13T17:13:58.476545083+01:00] Starting k3s v1.17.0+k3s.1 (0f644650)
[...]
# ./k3s kubectl get node
NAME           STATUS   ROLES    AGE   VERSION
rguichard-x1   Ready    master   59s   v1.17.0+k3s.1
```

39 secondes. 39 secondes pour un Kubernetes mono-master à jour. Pas mal. Depuis
la v1.0.0, k3s supporte le [multi-master à titre
expérimental](https://rancher.com/docs/k3s/latest/en/installation/ha-embedded/).

Containerd et Flannel sont installés mais on pourrait considérer qu'une
container runtime et un pod network addon sont un minimum nécessaire. K3s a
inclu d'autres surprises :

- Traefik comme Ingress Controller
- L'auto-déploiement de manifests
- Helm v3


### Kubernetes in Docker

Ce qui est intéressant de voir c'est qu'on peut facilement faire tourner k3s
dans Docker. Pour ça Rancher fourni un outil qui vient se placer au dessus de
k3s nous aidant à le déployer dans des conteneurs Docker :
[k3d](https://github.com/rancher/k3d).

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

Ça marche plutôt bien. C'est même encore plus rapide.

### k3s dans une CI

Depuis quelques années, la plupart des providers CI
(travis-ci, circle-ci, concourse etc) fournissent un environement Docker pour
pouvoir faire tourner nos jobs au sein de conteneurs dont nous avons nous même
construit les images. Les avantages sont nombreux, assurance de la cohérence
des versions, agnosticité du provider, environement de tests et de production
aussi proches que possible etc.

Mais désormais lorsque l'on veut tester notre application, c'est Kubernetes qui
va se charger de la faire fonctionner, [Docker ou une autre container
runtime](https://particule.io/blog/container-runtime/) se charge seulement
d'exécuter le conteneur. On a donc besoin de tester nos fichiers yaml et
n'importe quelle primitive fournie par Kubernetes.

Nous allons donc nous servir de k3s pour démarrer un environement Kubernetes
sur un projet Travis-CI.

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

Pas de suprise, tout s'exécute normalement et en quelques dizaines de secondes,
nous avons un environement Kubernetes déployé chez Travis-CI sur lequel nous
pouvons faire les tests de n'importe quelle application !


[Romain Guichard](https://www.linkedin.com/in/romainguichard/), CEO &
Co-founder
