---
Title: "Kubernetes 1.20"
Date: 2020-12-09
Category: Kubernetes
Summary: Kubernetes 1.20 est sortie, passons en revue les nouveautés
Author: Kevin Lefevre
image: images/thumbnails/kubernetes-1.20.png
lang: fr
---

[Une nouvelle version de Kubernetes est
disponible](https://kubernetes.io/blog/2020/08/26/kubernetes-release-1.19-accentuate-the-paw-sitive/).
La 1.20 est sortie hier et c'est l'occasion pour nous de revenir sur les
nouveautés.

Le cycle de release est de retour à la normal avec un cycle de 11 semaines.

Le [changelog](https://relnotes.k8s.io/?releaseVersions=1.20.0)
est disponible également [en version plus
lisible](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.20.md).

Le but de cet exercice n'est pas de paraphraser le CHANGELOG mais bien de vous
donner nos insights et de pointer les éléments qui sont, *selon nous*,
importants et/ou intéressants. Ce passage en revue de la 1.20 n'est donc ni
exhaustive, ni impartiale ;)

### Docker est déprécié

Le support de Docker est effectivement déprécié, cette nouvelle en aura surpris
plus d'un. Pourquoi ce n'est pas grave ? Nous en parlions
[ici](https://particule.io/blog/kubernetes-docker-support/)

### Alpha : Graceful node shutdown

Lors de la mise à jour des nœuds Kubernetes, une opération de `drain` est en
général réalisée afin de retirer les pods s'exécutant sur le nœuds dans le but
de le mettre a jour et de le redémarrer par exemple.

Dans le cas ou un mode n'est pas drainé, la [Feature
Gate](https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/)
`GracefulNodeShutdown` permet au Kubelet de détecter le shutdown d'un nœud et
de rajouter un délai supplémentaire dans le but de terminer proprement les pods
s'exécutant sur le nœud.

### Les snapshot passent en GA

[CSI](https://kubernetes.io/blog/2019/01/15/container-storage-interface-ga/)
fourni une [manière
standard](https://github.com/kubernetes-csi/external-snapshotter) de créer des
snapshot pour les plugins qui le supportent via le [`snapshot
controller`](https://github.com/kubernetes-csi/external-snapshotter).

Ce composant ainsi que les [Custom Resources Definition
utilisées](https://github.com/kubernetes-csi/external-snapshotter/tree/master/client/config/crd)
passent en `v1` et fournissent une interface stable sur laquelle les solution de
stockage peuvent s'appuyer pour fournir des fonctionnalité de backup / snapshot
avancées.

### Kubectl debug est en beta

`kubectl debug` permet de debugger des pods dans le cas ou un `exec` est difficile
voir impossible (eg. [distroless](https://github.com/GoogleContainerTools/distroless))

Nous la [présentions en 1.18](https://particule.io/blog/kubernetes-1.18/#kubectl-debug), elle passe aujourd'hui en beta.

### Autres changements

* Les `runtimeclasses` permettant d'utiliser de multiple [container runtime](https://particule.io/blog/container-runtime/)
    passent en `v1`
* Nouvelle implémentation de [dual stack IPv4/ IPv6](https://kubernetes.io/docs/concepts/services-networking/dual-stack/)
* Dans le but d'utiliser un langage non offensif, le terme `master` sera peu à
    peu remplacé par `controlplane` (comme Github avec la branch `main`) à commencer par les
    labels `kubeadm` : `node-role.kubernetes.io/master` devient
    `node-role.kubernetes.io/control-plane` et
    `node-role.kubernetes.io/master:NoSchedule` devient
    `node-role.kubernetes.io/control-plane:NoSchedule`

### Conclusion

A dans trois mois pour Kubernetes 1.21 !

L'équipe [Particule](https://particule.io)
