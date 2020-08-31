---
Title: "Kubernetes 1.19"
Date: 2020-08-31
Category: Kubernetes
Summary: Kubernetes 1.19 est sortie, passons en revue les nouveautés
Author: Kevin Lefevre
image: images/thumbnails/kubernetes-1.19.png
lang: fr
---

C'est la rentrée et comme tous les trois mois, une nouvelle version de Kubernetes sort. La 1.19 est
sortie il y a quelques jours et c'est l'occasion pour nous de revenir sur les
nouveautés.

En réalité cette release arrive 5 mois après la précédente (la 1.18 étant
sortie le 25 Mars 2020. La communauté souhaitant se laisser un peu plus de temps
pour accpeter des feature et patch en raison du COVID-19 ainsi que des
évènements Black Live Matter.

Le [changelog est consequent](https://relnotes.k8s.io/?releaseVersions=1.19.0)
mais on peut aussi en trouver [une version plus
lisible](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.19.md).

Le but de cet exercice n'est pas de paraphraser le CHANGELOG mais bien de vous
donner nos insights et de pointer les éléments qui sont, *selon nous*,
importants et/ou intéressants. Cette review de la 1.19 n'est donc ni
exhaustive, ni impartiale ;)

## Ce qui change !

### Support étendu a 12 mois

La plus grosse annonce, plutôt "customer ortiented" est l'extension du support à
12 mois au lieu de 9 mois. En effet nous le voyons assez fréquemment chez nos
clients: rester à jour sur des tous les 3 mois est quasiment
impossible, même pour les startup/PME. Rester à jour sur une release
supporté 9 mois après est également difficile pour des entreprise moins agile.

Cette extension de 3 mois permettra de s'assurer que la version que vous
utilisez sera au moins supportée 12 mois après sa sortie avant de devenir
*End Of Life* (EOL) contre 9 précédemment.

### Ingress sort de la beta

Il existe une règle dans la communauté comme quoi une fonctionnalité ne peut rester
dans la même version pendant plus de 9 mois. A la fin de ce temps, elle doit
soit être abandonnée soit passer en `v1`.

Une exception a été faite pour les *Ingress* qui sont majoritairement utilisée
et tous les *Ingress Controller* reposent sur elles. Il est donc plus prudent de
les passer en `v1` et de commencer a travailler sur une `v2` potentielle tout en
standardisant la `v1`.

Les objets *Ingress* sont maintenant disponibles dans l'API `networking/v1`.

Il existe un problème similaire actuellement avec les [Pod Security
Policy](https://particule.io/blog/kubernetes-psp/) qui sont aujourd'hui dans le
même cas. Le discussion est disponible
[ici](https://github.com/kubernetes/enhancements/issues/5). Il n'existe pour le
moment aucune solution viable de remplacement et selon les règles, les PSP
devrait sortir définitivement de Kubernetes à la version 1.22. A suivre pour
voir ce qu'il sera décidé d'ici la.

<https://github.com/kubernetes/enhancements/issues/1453>

### Larges cluster: EndpointSlice activé par defaut

Présentés en 1.16, les [*EndpointSlices*](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/) apportent une solution aux problèmes de
scalabilité de `kube-proxy` dans les cas de large cluster.

Par defaut tous les endpoints d'un services sont stocké dans un seul objets de
type *Endpoint*, dans le cas de large cluster, ces objets peuvent devenir très
grands et causer une charge importante sur le control plane.

Les *EndpointSlices*  permettent de découper ces *Endpoints* en sous objets, qui
regroupent chacun par défaut 100 endpoints (extensible à 1000).

Cette fonctionnalité sera maintenant activé par defaut pour les nouveaux cluster
en 1.19 et devrait réduire considérablement les problèmes de scalabilité liés au
nombre de pods.

<https://github.com/kubernetes/enhancements/issues/1412>

### ConfigMap et Secrets immuables

Cette nouvelle fonctionnalité permet de créer de *Secret* et *ConfigMap* qui
seront par la suite `immutable`. Cela permet notamment deux choses:

* protection contre les mise a jour accidentelle qui peuvent provoquer une
    interruption de service
* optimiser les performance puisque les objet qui seront immuable n'ont pas
    besoin d'être contrôler par le control plane pour vérifier les mise à jour

En pratique un champ a été rajouté dans les specs des *Configmap*:

```
immutable: true
```

Une fois créé il est impossible de revenir en arrière et de la rendre `mutable`,
a seule solution est de la supprimée et de la recreer.

<https://github.com/kubernetes/enhancements/issues/1412>

## Ce qui disparaît !

TODO

### Conclusion

A dans trois mois pour Kubernetes 1.20 !

L'équipe [Particule](https://particule.io),
[**Kevin Lefevre**](https://www.linkedin.com/in/kevinlefevre/)
[**Romain Guichard**](https://www.linkedin.com/in/romainguichard/)
