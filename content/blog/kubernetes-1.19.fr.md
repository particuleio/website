---
Title: "Kubernetes 1.19"
Date: 2020-08-31
Category: Kubernetes
Summary: Kubernetes 1.19 est sortie, passons en revue les nouveautés
Author: Kevin Lefevre
image: images/thumbnails/kubernetes-1.19.png
lang: fr
---

C'est la rentrée et comme tous les trois mois, [une nouvelle version de
Kubernetes est
disponible](https://kubernetes.io/blog/2020/08/26/kubernetes-release-1.19-accentuate-the-paw-sitive/).
La 1.19 est sortie il y a quelques jours et c'est l'occasion pour nous de
revenir sur les nouveautés.

En réalité cette version arrive 5 mois après la précédente (la 1.18 étant
sortie le 25 Mars 2020). La communauté souhaitant se laisser un peu plus de temps
pour accepter des fonctionnalités et patch en raison du COVID-19 ainsi que des
évènements Black Live Matter

Le [changelog est conséquent](https://relnotes.k8s.io/?releaseVersions=1.19.0)
et disponible également [en version plus
lisible](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.19.md).

Le but de cet exercice n'est pas de paraphraser le CHANGELOG mais bien de vous
donner nos insights et de pointer les éléments qui sont, *selon nous*,
importants et/ou intéressants. Ce passage en revue de la 1.19 n'est donc ni
exhaustive, ni impartiale ;)

### Support étendu à 12 mois

La plus grosse annonce orienté client est l'extension du support à 12 mois au
lieu de 9 mois.

En effet nous le voyons assez fréquemment chez nos clients: rester à jour tous
les 3 mois est quasiment impossible, même pour les startup/PME. Rester à jour
sur une version supportée 9 mois après est également difficile pour des
entreprises moins agiles.

Cette extension de 3 mois permettra de s'assurer que la version que vous
utilisez sera au moins supportée 12 mois après sa sortie avant de devenir
*End Of Life* (EOL) contre 9 mois précédemment.

### Ingress sort de la beta

Il existe une règle dans la communauté comme quoi une fonctionnalité ne peut rester
dans la même version pendant plus de 9 mois. A la fin de ce temps, elle doit
soit être abandonnée soit passée en `v1`.

Une exception a été faite pour les
[*Ingress*](https://kubernetes.io/docs/concepts/services-networking/ingress/)
qui sont majoritairement utilisées: tous les [*Ingress
Controller*](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/)
reposent sur elles. Il est donc plus prudent de les passer en `v1` et de
commencer a travailler sur une `v2` potentielle tout en standardisant la `v1`.

Les objets *Ingress* sont maintenant disponibles dans l'API `networking/v1`.

Il existe un problème similaire actuellement avec les [Pod Security
Policy](https://particule.io/blog/kubernetes-psp/) qui sont aujourd'hui dans le
même cas. La discussion est disponible
[ici](https://github.com/kubernetes/enhancements/issues/5). Il n'existe pour le
moment aucune solution viable de remplacement et selon les règles, les PSP
devrait sortir définitivement de Kubernetes à la version 1.22. A suivre pour
voir ce qu'il sera décidé d'ici là.

<https://github.com/kubernetes/enhancements/issues/1453>

### Larges cluster: EndpointSlice activés par défaut

Présentés en 1.16, les
[*EndpointSlices*](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/)
apportent une solution aux problèmes de scalabilité de `kube-proxy` dans les cas
de large cluster.

Par défaut tous les
[endpoints](https://kubernetes.io/docs/concepts/services-networking/service/)
d'un service sont stockés dans un seul objet de type *Endpoint*. Dans le cas de
large cluster, ces objets peuvent rapidement devenir très lourds et causer une
charge importante sur le control plane.

Les *EndpointSlices* permettent de découper ces *Endpoints* en sous objets, qui
regroupent chacun par défaut 100 endpoints (extensible à 1000).

Cette fonctionnalité sera maintenant activée par défaut pour les nouveaux cluster
en 1.19 et devrait réduire considérablement les problèmes de scalabilité liés au
nombre de pods.

<https://github.com/kubernetes/enhancements/issues/1412>

### ConfigMap et Secrets immuables

Cette nouvelle fonctionnalité permet de créer de *Secret* et *ConfigMap* qui
seront par la suite `immutable`. Cela permet notamment deux choses:

* Protection contre les mises à jour accidentelles qui peuvent provoquer une
    interruption de service.
* Optimiser les performance puisque les objet qui seront immuables n'ont pas
    besoin d'être contrôlés par le control plane pour vérifier les mises à jour.

En pratique un champ a été rajouté dans les spécifications des *Configmap*:

```
immutable: true
```

Une fois créé il est impossible de revenir en arrière et de la rendre `mutable`,
la seule solution est de la supprimer et de la recréer.

<https://github.com/kubernetes/enhancements/issues/1412>

### Kubernetes et Windows

Depuis un moment, grâce a
[CRI](https://kubernetes.io/blog/2016/12/container-runtime-interface-cri-in-kubernetes/),
il est possible de manière transparente de changer de [container
runtime](https://particule.io/blog/container-runtime/) sur Linux. Windows était
cependant limité à Docker. Avec la 1.19, [`containerd`](https://containerd.io/)
passe en beta sur Windows, ce qui permettra a terme de se passer de Docker comme
sur Linux.

Coté stockage, [CSI Proxy](https://github.com/kubernetes-csi/csi-proxy) passe
également en beta, celui ci permet de facilité l'utilisation de certains
[drivers CSI](https://kubernetes-csi.github.io/docs/drivers.html) sur les nœud
Windows.

### Autres changements

* CoreDNS mise a jour en `v1.7.0`: le noms des métriques Prometheus change, ce qui
    impose une réécriture des dashboard/ requêtes.

### Conclusion

A dans trois mois pour Kubernetes 1.20 !

L'équipe [Particule](https://particule.io)
