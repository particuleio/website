---
Title: Utiliser les PodSecurityPolicy avec Kubernetes Kapsule de Scaleway
Date: 2020-07-02
Category: Kubernetes
Summary: Les PodSecurityPolicy peuvent être activées sur Kubernetes Kapsule de Scaleway mais quelques configurations sont nécessaires pour que cela fonctionne... Comme chez les autres ?
Author: Romain Guichard
image: images/thumbnails/logo-scaleway-elements.png
imgSocialNetwork: images/og/kapsule-psp.png
lang: fr
---

Kubernetes Kapsule est le service de Kubernetes managé de Scaleway. Nous avons
déjà traité la présentation du service dans un
[précédent article](https://particule.io/blog/scaleway-kapsule/). Nous avions
été assez élogieux, mettant particulièrement en avant le travail effectué sur
le provider Terraform permettant de déployer et de manager, entièrement en
infrastructure as code, nos clusters Kubernetes.

C'est d'ailleurs sur ce point que commence notre problème. La ressource
Terraform permettant de déployer des clusters Kubernetes chez Scaleway permet
de configurer ces clusters en choisissant
[les Admission Controllers à
activer](https://www.terraform.io/docs/providers/scaleway/r/k8s_cluster_beta.html#admission_plugins).

**C'est quoi un Admission Controller ?**

Un Admission Controller est controller dans Kubernetes qui permet
d'effectuer un vérification sur une requête à l'API **après** l'authentification
et **avant** l'exécution de la requête. Ces Admission Controllers peuvent
valider qu'une requête correspond à certaines règles mais peuvent aussi
modifier la requête pour la forcer à respecter une règle. On parle de
*validating* ou *mutating* Admission Controller.


J'ai donc souhaité activer les `PodSecurityPolicy` sur mon cluster. [On a déjà
parlé de cet objet chez Particule](https://particule.io/blog/kubernetes-psp/),
il s'agit de règles de sécurité concernant
nos pods que l'Admission Controller va vérifier avant d'appliquer ou non le pod
dans notre cluster. On peut par exemple interdir les pods qui utilisent le mode
`privileged`, interdire les conteneurs qui tournent en root ou ceux qui tentent
d'utiliser des `hostPath`. C'est extrêmement puissant.

Extrêmement puissant mais ça ne marche pas out of the box. Et Kapsule de
Scaleway ne fait pas exception.

Voici déjà le code Terraform pour déployer l'Admission Controller :

```terraform
resource "scaleway_k8s_cluster_beta" "k8s" {
  name = "particule"
  version = "1.18.2"
  cni = "weave"
  admission_plugins = ["PodSecurityPolicy"]
}
```

Normalement cela va très vite mais là étonnement, mon node reste en `NotReady`
après plus de 10 minutes... Étrange.

```console
NAME                                             STATUS     ROLES    AGE   VERSION
scw-particule-commonpool-dbfe057a9ee64e56b50f9   NotReady   <none>   11m   v1.18.2
```

Le problème est qu'activer les PodSecurityPolicy ça ne suffit pas, pire ça
"casse" le cluster si rien d'autre n'est effectué.

Comme nous l'avons déjà expliqué, une fois les PSP activées, tous les pods qui
souhaiteront être schédulés devront fournir une PSP à l'API Server afin que
celui ci valide qu'ils respectent bien les règles. Si aucune PSP n'est
disponible ou qu'un pod n'a le droit d'accéder à aucune d'entre elles, l'API
Server lui refusera le déploiement.

Et c'est exactement ce qu'il se passe chez Kapsule. Aucun pod ne peut se
schéduler car :

- Aucune PSP n'est présente
- Aucun droit n'est donné pour utiliser une PSP

On va donc corriger cela en créant une PSP `privileged` qui permettra
d'absolument tout faire (comme si il n'y avait pas de PSP en fin de compte) et
autoriser l'ensemble du cluster à utiliser cette PSP.

```yaml
---
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: privileged
spec:
  allowPrivilegeEscalation: true
  allowedCapabilities:
  - '*'
  allowedUnsafeSysctls:
  - '*'
  fsGroup:
    rule: RunAsAny
  hostIPC: true
  hostNetwork: true
  hostPID: true
  hostPorts:
  - max: 65535
    min: 0
  privileged: true
  runAsUser:
    rule: RunAsAny
  seLinux:
    rule: RunAsAny
  supplementalGroups:
    rule: RunAsAny
  volumes:
  - '*'
---
```

Puis le ClusterRole et le ClusterRoleBinding qui permettront à tous les
éléments authentifiés de votre cluster d'utiliser (`use`) la PSP :

```yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: psp:privileged
rules:
- apiGroups:
  - policy
  resourceNames:
  - privileged
  resources:
  - podsecuritypolicies
  verbs:
  - use
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: psp:any:privileged
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: psp:privileged
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:authenticated
```

On applique tout ce petit monde et on attend tranquillement que les pods CNI et
kube-proxy se déploient pour que notre node passe en `Ready`.

```console
NAME                                             STATUS   ROLES    AGE    VERSION
scw-particule-commonpool-dbfe057a9ee64e56b50f9   Ready    <none>   17m   v1.18.2
```

### Et chez les autres Cloud Provider ?

Il est évidemment important de noter qu'il ne s'agit pas d'une faute de
configuration de Scaleway. Le composant demandé est bien appliqué, il manque
seulement certaines ressources que n'importe quel utilisateur peut créer pour
profiter pleinement de la fonctionnalité. On pourra aussi remarquer que GKE ne
fourni pas non plus de PSP lors de l'activiation de celles ci. Quant à EKS, une
PSP ressemblant beaucoup à la notre est appliquée par défaut.


### Conclusion

Les PSP sont des éléments importants de tout cluster et devraient toujours être
pensées et crées en même temps que le cluster. Les appliquer ou [les supprimer
sur un cluster *running* nécessite d'être extrêmement rigoureux au risque de
casser le cluster en
fonctionnement](https://github.com/aws/containers-roadmap/issues/401).

Merci à [Patrik](https://twitter.com/PatrikCyvoct) de Scaleway pour m'avoir
pointé dans la bonne direction.


[**Romain Guichard**](https://www.linkedin.com/in/romainguichard), CEO &
co-founder

