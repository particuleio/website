---
Title: "Kubernetes 1.21"
Date: 2021-04-09
Category: Kubernetes
Summary: Kubernetes `1.21` est sortie, passons en revue les nouveautés
Author: Kevin Lefevre
image: images/thumbnails/kubernetes-1.21.png
lang: fr
---

[Une nouvelle version de Kubernetes est
disponible](https://kubernetes.io/blog/2021/04/08/kubernetes-1-21-release-announcement).
La `1.21` est sortie hier et c'est l'occasion pour nous de revenir sur les
nouveautés.


Le [changelog](https://relnotes.k8s.io/?releaseVersions=1.21.0)
est disponible également [en version plus
lisible](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.21.md).

Le but de cet exercice n'est pas de paraphraser le CHANGELOG mais bien de vous
donner nos insights et de pointer les éléments qui sont, *selon nous*,
importants et/ou intéressants. Ce passage en revue de la `1.21` n'est donc ni
exhaustive, ni impartiale ;)

### Ce qui passe en GA

Plusieurs ressources sont maintenant stables, c'est le cas des cronjob qui
permettent de lancer des
[`Jobs`](https://kubernetes.io/docs/concepts/workloads/controllers/job/) à
intervalle régulier.

On notera également les
[`PodDisruptionBudget`](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)
qui permettent d'assurer un niveau minimum de service dans le cas de mise à jour
par exemple.

Dans les fonctionnalités un peu cachées, les
[`EndpointsSlices`](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/)
sont également stables, nous en avions [parlés plus en
détail](https://particule.io/blog/kubernetes-1.19/) lors de la sortie de la
`v1.19`.

### La killer feature attendue de tous

Si vous avez déjà du vous `exec` dans un pod avec plusieurs conteneurs vous
êtes surement déjà tombés là dessus:

```
k -n namespace exec -it mypod -- /bin/sh
Defaulting container name to container0.
Use 'kubectl describe pod/mypod -n mynamespace' to see all of the containers in this pod.
```

Et ensuite devoir rajouter `-c container` pour spécifier le bon conteneur. Ce
temps est révolu puisqu'il est maintenant possible de rajouter l'annotation
`kubectl.kubernetes.io/default-container` sur vos pods et enfin regagner ces
précieuses 5 secondes de vie

### Les pods security policy sont dépréciées

C'est arrivé, elles vont officiellement disparaitre en version 1.25. Rien n'est
prévu dans Kubernetes pour les remplacer et il est recommandé de passer à une
solution tierce.

Pour plus d'information à ce sujet nous vous invitons à parcourir notre article
qui traite de la dépréciation des
[`PodSecurityPolicies`](https://particule.io/blog/kubernetes-psp-deprecated/)
ainsi que notre [deep dive sur Kyverno](https://particule.io/blog/psp-kyverno/)
qui est selon nous un très bon choix de remplacement.

### Ce qui peut casser

Un des points importants qui peut facilement passer à la trappe : si vous faites
du Kubernetes avec `kubeadm`, celui ci va activer automatiquement le cgroup
driver à `systemd` pour les nouveaux déploiements. Il est important d'avoir le
même `cgroup` [configuré dans votre container
runtime](https://kubernetes.io/docs/setup/production-environment/container-runtimes/#cgroup-drivers),
certaines runtime utilisent `cgroupfs` par défaut (c'est le cas de containerd
par exemple). A partir de la version 1.22, `kubeadm` activera par défaut
`systemd` pour tous les déploiements, c'est à ce moment là qu'il faudra faire
attention à l'update de vos nodes, qui pourraient potentiellement casser à cause
de ce changement.

### Conclusion

A dans trois mois pour Kubernetes `1.22` !

L'équipe [Particule](https://particule.io)
