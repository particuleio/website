---
Title: "Les namespaces hiérarchiques"
Date: 2020-10-26
Category: Kubernetes
Summary: Comment déléguer la création de namespace dans Kubernetes ?
Author: Kevin Lefevre
image: images/thumbnails/kubernetes-generic.png
lang: fr
---

La communauté Kubernetes est décomposée en *Special Interest Group* (SIG). Le
[SIG multi-tenancy](https://github.com/kubernetes-sigs/multi-tenancy) est le
groupe de travail qui se penche sur l'aspect multi-tenant de Kubernetes.

La multi-tenancy est la fait de partager une ressources entre différents tiers
qui ne se font pas forcement de confiance et doivent et/ou peuvent avoir des
droits et de permissions différentes. Ces tiers sont appelés des *tenants*. Ce
terme a également été repris par différents fournisseurs de Cloud, notamment
OpenStack qui appelaient ses projets tenants avant de les appeler *Projects*,
c'est une notion également reprise chez Google Cloud ou Azure avec les
*Projects* et les *Resources Groups* respectivement.

Il est possible de déployer de multiple cluster Kubernetes au seins d'une
même organisation mais cela n'est pas toujours possible pour des raisons de coût,
d'organisation interne ou encore de complexité de gestion.

Le SIG multi=tenancy travaille sur différents projets qui ont pour but de
segmenter un seul et unique cluster Kubernetes. Ils travaillent pour le moment
sur 3 projets principaux:

* [Tenant Operator](https://github.com/kubernetes-sigs/multi-tenancy/blob/master/tenant) 
dont le but et de facilité la création de *Tenant* sur un cluster via
l'utilisation de [Custom Resource
Definition](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)
* [Virtual Cluster](https://github.com/kubernetes-sigs/multi-tenancy/blob/master/incubator/virtualcluster)
dont le but est de séparer les cluster Kubernetes en de multiples sous cluster
pour une utilisation plus hermétique
* [Hierararchical namespaces (aka HNC)](https://github.com/kubernetes-sigs/multi-tenancy/blob/master/incubator/hnc)
dont le but est de pouvoir organiser les namespaces sous forme d'arborescence
avec une notion d'héritage.

Nous allons nous intéresser à ce dernier puisqu'il répond selon nous à une
problématique que nous avons souvent rencontrée, à savoir, comment donner des
droits à différentes équipes, sur un même cluster, tout en leur offrant une
certaine flexibilité et autonomie.

Dans un cluster Kubnernetes, il existe deux types de ressources:

* Les ressources *namespacées* qui appartiennent à un namespaces.
* Les ressources *cluster non namespacés* telles que les noeuds et les namespaces.

Si l'on respecte les bonnes pratiques, il est courant de limiter les droits des
utilisateurs du cluster aux resources namespacées. [Il existe même des
*ClusterRoles* par défaut afin de déléguer les droits administrateur sur tout un
namespace](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#user-facing-roles).

Cette solution fonctionne très bien mais nécessite donc une création du
namespace au préalable ainsi que la création des droits et rôles associés. La
délégation ne peut se faire uniquement que sur un seul namespace qui doit être
connu à l'avance.

Imaginons maintenant un cas pratique ou l'administration des clusters serait
gérée par une équipe. Et le déploiement des applications métier par une autres.

Il n'est pas souhaitable que l'équipe responsable des applications soit
administrateur du cluster. Si cette même équipe opte pour une déploiement des
micro services par namespace (un namespace = un micro-service), cela signifie une
interaction avec l'équipe responsable de la gestion des cluster afin de créer au
préalable les namespaces et déléguer les droit à l'équipe applicative.

Dans un soucis d'automatisation permanent, cette solution n'est pas viable,
nous souhaitons que les équipes puissent être administrateur de leur propre
namespace mais également de pouvoir respecter les bonnes pratiques, à savoir
séparer les différents projets et micro services dans des namespaces différents.

### Les namespaces hiérarchique

[Les namespace hiérarchiques ont été introduits
récemment](https://kubernetes.io/blog/2020/08/14/introducing-hierarchical-namespaces/)
et permettent de répondre à cette problématique en organisant les namespace sous
forme d'arbre de dépendance: les namespaces et leur sous namespaces.

Pour cela la solution intègre différents composants:

* Les CRD *SubnamespaceAnchor* et *HierarchyConfiguration*.
* Un contrôleur à déployer dans le cluster.
* Une CLI intégrée a `kubectl`.

### Déploiement du contrôleur

Dans un premier temps le contrôleur doit être déployer sur le cluster:

```console
kubectl apply -f https://github.com/kubernetes-sigs/multi-tenancy/releases/download/hnc-v0.5.3/hnc-manager.yaml
```

### Utilisation de la CLI

[Krew](https://github.com/kubernetes-sigs/krew) est le gestionnaire de plugin
pour `kubectl` et HNC dispose d'un plugin prêt a l'emploi, une fois le
contrôleur installer dans le cluster, le plugin doit être intégré localement à
`kubectl`:

```console
kubectl krew install hns
```

Il est ensuite possible possible de lister les namespaces et leur hiérarchie:

```console
kubectl hns tree --all-namespaces
default
elastic-system
external-dns
flux
kube-node-lease
kube-public
kube-system
kubernetes-dashboard
metallb-system
metrics-server
monitoring
nginx-ingress
node-problem-detector
rook-ceph
sealed-secrets
```

Pour le moment nous n'avons aucun sous namespaces.

### Création de sous namespaces via la CLI

Le plugin `kubectl` permet de créer des sous namespaces via la CLI, par exemple:

```
kubectl hns create integration -n team-a
kubectl hns create recette -n team-a

kubectl hns tree --all-namespaces

default
elastic-system
team-a
├── integration
└── recette
external-dns
flux
hnc-system
kube-node-lease
kube-public
kube-system
kubernetes-dashboard
metallb-system
metrics-server
monitoring
nginx-ingress
node-problem-detector
rook-ceph
sealed-secrets
```

En réalité, ce qu'il se passe derrière la CLI est la création de deux ressources de
type *NamespaceAnchor* dans le namespace `team-a` qui créer les sous namespaces
`integration` et `recette`.

À la différence des namesapces, les ressources *NamespaceAnchor* sont des
ressources namespacés qui appartiennent au namespace parent.

Ces ressources peuvent donc être plus facilement déléguées puisqu'il est
possible de donner des droits de créer des sous namespaces uniquement dans un
namespace donné tout en empêchant les utilisateur de toucher a d'autres
namespaces.

La force des namespaces hiérarchique réside également dans la réplication de
certaines ressources par défaut, notamment les *Roles* et *RoleBindings*. Ces
derniers sont automatiquement répliqués dans les sous namespaces.

Cela permet de donner uniquement des droit d'administrateur à la team A dans le
namespaces `team-a` et ses droits seront automatiquement répliqués dans les sous
namespaces.

Il peut être nécessaire de copier d'autres ressources entre les namespaces d'une
même hiérarchie, par défaut, seul les *Role* et *ClusterRoles* sont répliqués
mais il est possible de repliquer par exemple les *Secrets* ont changeant la
configuration du contrôleur:

```
kubectl edit hncconfiguration config

apiVersion: hnc.x-k8s.io/v1alpha1
kind: HNCConfiguration
metadata:
  name: config
spec:
  types:
    ...
    - apiVersion: v1
      kind: Secret
      mode: propagate
```

Cette configuration propagera automatiquement les secrets d'un namespaces
parents vers un namespaces enfant par exemple.

### Intégration avec GitOps

Les commandes vu percement se basent sur la CLI `kubectl` mais en realité la CLI ne
fait qu'interagir avec les *CRD* utilisées par le contrôleur.

Ces *CRD* permettent de se passer de la CLI et de s'intégrer facilement avec des
solutions GitOps. Par exemple, pour créer un sous namespace sans la CLI, il
suffit de définir un objet de type *NamespaceAnchor* dans le namespace parent:

```
$ kubectl apply -f - <<EOF
apiVersion: hnc.x-k8s.io/v1alpha1
kind: SubnamespaceAnchor
metadata:
  namespace: parent
  name: child
EOF
```

Grâce à cela, il est possible d'intégrer les namespaces hiérarchiques dans un
workflow GitOps de manière sécurisée.

Chez particule nous sommes de fervents adeptes de [FluxCD](https://fluxcd.io/)
dont nous vous avons [souvent](https://particule.io/blog/flux-semver/)
[parlé](https://particule.io/blog/cicd-concourse-flux/).


Il est possible de donner par exemple un accès a FluxCD à une équipe dans un
namespace donné avec le workflow suivant:

1. Création d'un namespace racine dans lequel une équipe sera administrateur.
2. Déploiement de flux avec des droit limités uniquement dans ce namespaces.
3. Ajouter à flux le droit de créer des objets de type *NamespaceAnchor* dans ce
   namespace.

Les utilisateurs de ce namespace pourront alors déployer des ressources dans ce
namespace et auront également la possibilité de créer des sous namespaces dans
lesquels FluxCD aura également le droit de déployer automatiquement en parfaite
autonomie, sans avoir besoin de communiquer avec l'équipe en charge des cluster
pour creer les namespaces et/ou de droit sur des objets de type *non
namespacés*.

### Conclusion

Les namespace hiérarchiques permettent de pousser la segmentation et
l'automatisation encore plus loin. Permettant de garder la sécurité offerte par
les namespaces tout en offrant plus de souplesse aux équipes exploitant les
cluster Kubernetes, en leur permettant d'organiser leurs ressources comme bon
leur semble sans impacter les namespaces globaux du cluster.

Cette solution est idéale pour donner des droits sur des environnements de
recette ou d'intégration où les développeur peuvent tester et déployer à leur
gré sans risquer d'impacter le fonctionnement global du cluster.

Pour aller plus loin n'hésitez pas à vous orienter vers la [documentation
officielle](https://github.com/kubernetes-sigs/multi-tenancy/blob/master/incubator/hnc/docs/user-guide/how-to.md).

Pour vos projets Kubernetes, qu'ils soient mono ou multi tenants, on premises ou
Cloud public, [n'hesitez pas à nous contacter](mailto:contact@particule.io)

L'équipe [Particule](https://particule.io)
