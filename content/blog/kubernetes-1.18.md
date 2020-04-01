---
Title: "Kubernetes 1.18"
Date: 2020-03-31
Category: Kubernetes
Summary: Kubernetes 1.18 est sortie, passons en revue les nouveautés
Author: Romain Guichard
image: images/thumbnails/kubernetes-1.18.png
lang: fr
---

## Kubernetes 1.18

Comme tous les trois mois, une nouvelle version de Kubernetes sort. La 1.18 est
sortie il y a quelques jours et c'est l'occasion pour nous de revenir sur les
nouveautés.

Le [changelog est plutôt
énorme](https://relnotes.k8s.io/?releaseVersions=1.18.0) mais on peut aussi en
trouver [une version plus
lisible](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.18.md).

Le but de cet exercice n'est pas de paraphraser le changelog mais bien de vous
donner nos insights et de pointer les éléments qui sont, *selon nous*,
importants et/ou intéressants. Cette review de la 1.18 n'est donc ni
exhaustive, ni impartialle ;)

## Ce qui change !

### IngressClass

Une des "grosses" annonces de la 1.18, l'annotation `ingress.class` utilisée jusqu'à présent pour définir quels Ingress Controllers étaient configurés par la ressource Ingress devient un champ à part entière de la spec Ingress. Cette annotation n'était définie nul part dans la spec de l'API bien qu'elle soit implémentée sur la majeure partie des Ingress Controllers. Une nouvelle ressource fait donc son apparition `IngressClass`. Celle ci permet de définir la classe qui est ensuite réutilisée dans l'Ingress dans le champ `class` de l'Ingress.

```yaml
---
apiVersion: networking.k8s.io/v1beta1
kind: IngressClass
metadata:
    name: external-lb
spec:
    controller: example.com/ingress-controller
    parameters:
        apiGroup: k8s.example.com/v1alpha
        kind: IngressParameters
        name: external-lb
```

On peut voir que l'IngressClass va plus loin que la simple annotation. Elle définie en effet le nom de l'Ingress Controller mais peut aussi apporter différents éléments de configuration.

### Wildcard dans les IngressRules

On continue sur les Ingress avec la possibilité, désormais ouverte, d'utiliser des wildcards dans les règles `host` de nos Ingress. Auparavant, le champ `hosþ` devait matcher exactement un FQDN, dorénavant `*.particule.io` matchera `foo.particule.io` et `bar.particule.io`. Le wildcard ne match que le premier label (au sens DNS du terme), cela signifie que `foo.bar.particule.io` ne sera pas matché, ni `particule.io`.

C'est peu mais extrêmement utile.

<https://github.com/kubernetes/kubernetes/pull/88858>

### Les évictions, quand des limites sur l'ephemeral-storage atteintes, sont loguées

Le kubelet gère un mécanisme appelé l'éviction permettant de tuer des pods sans action utilisateur. A quoi ça sert ? Notamment à préserver les ressources de vos noeuds. En effet, afin de protéger [certains pods prioritaires](https://kubernetes.io/docs/concepts/configuration/pod-priority-preemption/), le kubelet peut décider que d'autres pods sont de trop et gênent le bon fonctionnement de ces pods prioritaires. Le mécanisme est aussi impliqué lorsqu'[un conteneur dépasse sa limite de mémoire](https://kubernetes.io/docs/concepts/configuration/manage-compute-resources-container/) et que votre noeud est à court de mémoire, dans ce cas, le pod serait très probablement *évicté*.

Ces évictions peuvent être loguées et depuis la 1.18, la metrique `kubelet_evictions` inclue 3 nouveaux signaux afin de tracker les évictions qui concernent notamment les limites concernant [l'ephemeral-storage](https://kubernetes.io/docs/concepts/configuration/manage-compute-resources-container/#local-ephemeral-storage)

- containerfs.ephemeral.limit - container ephemeral breaches its limit
- podfs.ephemeral.limit - pod ephemeral breaches its limit
- podfs.emptyDir.limit - pod emptyDir breaches its limit

<https://github.com/kubernetes/kubernetes/pull/87906>

### Kubectl debug

Pour investiguer les erreurs liées à un conteneur, nous passons en général par `kubectl exec` pour debug et acceder au conteneur, cette commande est bien pratique mais a quelques inconvénients :

- inutile si le pod est en `CrashLoop`
- Inutile si le pod est une image from `scratch` et ne dispose d'aucun outil de debugging
- Obligation d'installer des outils une fois `exec` dans le conteneur

Pour pallier à celà, la version 1.17 a introduit la notion d'[EphemeralContainer](https://kubernetes.io/docs/concepts/workloads/pods/ephemeral-containers/), qui permet de lancer un conteneur de ["debug"](https://kubernetes.io/docs/tasks/debug-application-cluster/debug-running-pod/#debugging-with-ephemeral-debug-container) dans le pod basé sur une autre image.

La version 1.18 continue sur cette lancée et intègre les EphemeralContainer à `kubectl` via la commande `kubectl alpha debug` qui permet de lancer rapidement un EphemeralContainer lié à un pod. Pour cela il faut au préalable activer la [FeatureGate](https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates ) sur les differents composants.

#### Mini démo

Debug d'un pod [*Traefik*](https://containo.us/traefik/) qui est une image from `scratch` avec juste un binaire Go.

```
$ kubectl alpha debug -it traefik-ingress-controller-f7d6d7b88-dzgb5 --image=ubuntu --target=traefik-ingress-lb-init
Defaulting debug container name to debugger-56nqc.
If you don't see a command prompt, try pressing enter.
root@traefik-ingress-controller-f7d6d7b88-dzgb5:/# ps aux
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root           1  0.0  0.0   1020     4 ?        Ss   12:12   0:00 /pause
root           7  3.3  0.3 777172 55776 ?        Ssl  12:12   0:07 /traefik --configfile=/config/traefik.toml
root          21  0.0  0.0  18504  3348 pts/0    Ss   12:15   0:00 /bin/bash
root          30  0.0  0.0  34400  2908 pts/0    R+   12:16   0:00 ps aux
```

### Configuration avancée des [Horizonal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)

Si vous avez l'habitude d'utiliser des autoscaling groups sur des fournisseurs de Cloud, vous êtes peut être familiers avec la notion de cooldown, qui défini le temps d'attente avant de déclencher un évènement de scale down. Avant Kubernetes 1.18, la seule option de configuration était au niveau du cluster avec l'option `--horizontal-pod-autoscaler-downscale-stabilization-window` par défaut à 5 minutes et certaines variables étaient hardcodées :

- scaleUpLimitFactor = 2.0
- scaleUpLimitMinimum = 4.0

Kubernetes 1.18 introduit de nouveaux champs `behavior` dans l'objet HPA qui permettent de définir les options de scale up et scale down par HPA et non pas au niveau du cluster. [La KEP est disponible ici](https://github.com/kubernetes/enhancements/blob/master/keps/sig-autoscaling/20190307-configurable-scale-velocity-for-hpa.md)

#### Quelques exemples

Scale up tres rapide et scale down graduel

```yaml
behavior:
  scaleUp:
    policies:
    - type: percent
      value: 900%
  scaleDown:
    policies:
    - type: pods
      value: 1
      periodSeconds: 600 # (i.e., scale down one pod every 10 min)
```

Si l'application démarre avec 1 pod le scale up se fera de la façon suivante : 1 -> 10 -> 100 -> 1000 alors que le scale down se fera d'un pod toutes les 10 minutes.

### Les Secrets et ConfigMaps peuvent être immuables

Grâce à la [FeatureGate](https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates ) `ImmutableEphemeralVolumes`, on peut désormais protéger nos Secrets et nos ConfigMaps en les rendant immuables. Cela permet d'éviter une modification malencontreuse.

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: mysecret
type: Opaque
data:
  username: cm9tYWluZ3VpY2hhcmQK
immutable: true
```

Et si vous tentez d'appliquer le même fichier avec un username différent :

```bash
kubectl apply -f secret.yml
The Secret "mysecret" is invalid: data: Forbidden: field is immutable when `immutable` is set
```

Pratique !

<https://github.com/kubernetes/kubernetes/pull/86377>

## Ce qui disparait !

### kube-apiserver

Normalement tous ces changements sont censés être déjà présents sur vos ressources mais il est important de noter que ces apiGroups sont désormais supprimés de l'API :

- Toutes les ressources sous `apps/v1beta1` et `apps/v1beta2` , il faut dorénavant utiliser `use apps/v1`
- Les ressources DaemonSets, Deployments, ReplicaSets sous `extensions/v1beta1`, il faut dorénavant utiliser `apps/v1`
- Les ressources NetworkPolicies sous `extensions/v1beta1`, il faut dorénavant utiliser `networking.k8s.io/v1`
- Les ressources PodSecurityPolicies sous `extensions/v1beta1`, il faut dorénavant utiliser  `policy/v1beta1`

<https://github.com/kubernetes/kubernetes/pull/85903>


### Conclusion

A dans trois mois pour Kubernetes 1.19 !


L'équipe [Particule](https://particule.io),
 [**Romain Guichard**](https://www.linkedin.com/in/romainguichard/)
[**Kevin Lefevre**](https://www.linkedin.com/in/kevinlefevre/)
