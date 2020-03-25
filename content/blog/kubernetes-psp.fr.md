---
Title: "Kubernetes deep dive: pod security policy"
Date: 2020-02-21T11:00:00+02:00
Category: Kubernetes
Summary: Comprendre en détails les PSP  ainsi que leur fonctionnement
Author: Kevin Lefevre
image: images/thumbnails/kubernetes.png
lang: fr
---

## Kubernetes: PodSecurityPolicy

### Introduction

Au début de Kubernetes, le contrôle sur les pods admis dans le cluster était
quasi inexistant, il n'y avait globalement que deux alternatives : autoriser
ou non les pods privilégiés. Ce mode "privilégié" correspondait au parramètre
`--privileged` de Docker.

Les *PodSecurityPolicies*, que nous appellerons PSP dans la suite de l'article, permettent justement de contrôler finement les specifications d'un pod avant de l'accepter sur le cluster. Elles permettent notamment de contrôler :

* Les types de volumes utilisés
* Le GID du point de montage d'un volume
* Système de fichier en lecture seule
* Les capabilities Kernel autorisées (sysctl, etc)
* Les profiles seccomp/apparmor
* Les Pods privilégiés
* Utilisation des hostPorts
* Les UID/GID utilisés par le Pod
* Les élévations de privilèges ( = sudo )

Alors à quoi cela ressemble ? Ci dessous l'exemple d'une policy `privileged` qui autorise tout, qui est le fonctionnement par défaut d'un cluster sans *PodSecurityPolicy* d'activé.

```yaml
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: privileged
  annotations:
    seccomp.security.alpha.kubernetes.io/allowedProfileNames: '*'
spec:
  privileged: true
  allowPrivilegeEscalation: true
  allowedCapabilities:
  - '*'
  volumes:
  - '*'
  hostNetwork: true
  hostPorts:
  - min: 0
    max: 65535
  hostIPC: true
  hostPID: true
  runAsUser:
    rule: 'RunAsAny'
  seLinux:
    rule: 'RunAsAny'
  supplementalGroups:
    rule: 'RunAsAny'
  fsGroup:
    rule: 'RunAsAny'
```

### Activer les PodSecurityPolicy

Les *PodSecurityPolicy* sont, à l'heure où j'écris cet article, en beta. Elles doivent être activées via un [admission controller](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/). Suivant votre méthode de déploiement il faudra ajouter à l'API server, l'admission controller `PodSecurityPolicy` et le redémarrer.

En ce qui concerne les services managés, la plupart supportent les PodSecurityPolicy:

* Activées par défaut dans EKS : [liste des admission controller](https://docs.aws.amazon.com/eks/latest/userguide/platform-versions.html)
* Activable sur GKE : `gcloud beta container clusters create [CLUSTER_NAME] --enable-pod-security-policy`
* Activable sur AKS : `az aks update --resource-group myResourceGroup --name myAKSCluster --enable-pod-security-policy`

Une mise en garde cependant, activer les PodSecurityPolicy sur un cluster existant peut potentiellement casser le cluster si les bonnes policies ne sont pas en place mais nous y reviendrons.

### Principe de fonctionnement

Le principe de fonctionnement des PSP n'est pas des plus plus intuitif. La première règle est que si les PSP sont activées sur le cluster, **tous** les pods doivent utiliser au moins une policy pour pouvoir être accepté par l'API server. Voilà la raison pour laquelle vous pouvez "casser" votre cluster en activant les PSP sans créer les policies adéquates. L'association entre les PSP et les pods qui les utilisent est effectuée via les [RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/). En effet chaque pod dispose d'un *ServiceAccount*, et chaque namespace dispose d'un *ServiceAccount* `default` utilisé par les pods qui ne spécifient pas explicitement de *ServiceAccount*. C'est donc ces ServiceAccount qui vont obtenir le droit d'utiliser les PSP.

Pour associer un *ServiceAccount* avec une PSP, il faut créer un *Role* ou *ClusterRole* pouvant utiliser cette policy et il faut ensuite utiliser un *RoleBinding* ou un *ClusterRoleBinding* pour associer le *ServiceAccount* à ce *Role* ou *ClusterRole*.

Exemple avec la PSP `privileged` vu plus haut :

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: psp:privileged
rules:
- apiGroups: ['policy']
  resources: ['podsecuritypolicies']
  verbs:     ['use']
  resourceNames:
  - privileged
```

```
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: psp:mySa:privileged
roleRef:
  kind: ClusterRole
  name: psp:privileged
  apiGroup: rbac.authorization.k8s.io
subjects:
# Authorize specific service accounts:
- kind: ServiceAccount
  name: mySa
  namespace: myNamespace
```

Il est également possible de specifier tous les *ServiceAccounts* d'un namespace:

```yaml
# Authorize all service accounts in a namespace:
- kind: Group
  apiGroup: rbac.authorization.k8s.io
  name: system:serviceaccounts:myNamespace
```

Ou encore tous les utilisateurs authentifiés de tous les namespaces:

```yaml
# Or equivalently, all authenticated users in a namespace:
- kind: Group
  apiGroup: rbac.authorization.k8s.io
  name: system:authenticated
```

#### Précedence

Une pod (via son ServiceAccount) peut donc être autorisé à utiliser plusieurs PSP, mais une seule sera appliquée.

Il faut tout d'abord faire la différence entre deux types de PSP, les `mutable
policy` et les `non mutable policy`. La plupart des PSP ne font que vérifier
que le pod respecte bien les règles (`non mutable policy`) mais certains annotations d'une PSP peuvent
permettre d'appliquer des règles seccomp et/ou apparmor au pod, dans ce cas la policy modifie le
pod, c'est donc une `mutable policy`.

Par exemple prenons une PSP:

```yaml
---
apiVersion: extensions/v1beta1
kind: PodSecurityPolicy
metadata:
  name: default
  annotations:
    seccomp.security.alpha.kubernetes.io/allowedProfileNames: 'docker/default'
    seccomp.security.alpha.kubernetes.io/defaultProfileName:  'docker/default'
spec:
  privileged: false
  allowPrivilegeEscalation: false
  allowedCapabilities: []  # default set of capabilities are implicitly allowed
  volumes:
  - 'configMap'
  - 'emptyDir'
  - 'projected'
  - 'secret'
  - 'downwardAPI'
  - 'persistentVolumeClaim'
  hostNetwork: false
  hostIPC: false
  hostPID: false
  runAsUser:
    rule: 'RunAsAny'
  seLinux:
    rule: 'RunAsAny'
  supplementalGroups:
    rule: 'RunAsAny'
  fsGroup:
    rule: 'RunAsAny'
```

et une autre:

```yaml
---
apiVersion: extensions/v1beta1
kind: PodSecurityPolicy
metadata:
  name: default
spec:
  privileged: false
  allowPrivilegeEscalation: false
  allowedCapabilities: []  # default set of capabilities are implicitly allowed
  volumes:
  - 'configMap'
  - 'emptyDir'
  - 'projected'
  - 'secret'
  - 'downwardAPI'
  - 'persistentVolumeClaim'
  hostNetwork: false
  hostIPC: false
  hostPID: false
  runAsUser:
    rule: 'RunAsAny'
  seLinux:
    rule: 'RunAsAny'
  supplementalGroups:
    rule: 'RunAsAny'
  fsGroup:
    rule: 'RunAsAny'
```

La différence entre les deux est l'annotation présente dans l'une et
inexistante dans l'autre. Si un pod ne spécifie pas de configuration seccomp
dans sa spec, la seconde policy sera matchée, car la première est
une `mutable policy`, c'est a dire qu'elle modifie le pod pour y
rajouter les annotations.

Maintenant que cela est clair, le choix de la PSP est fait de la manière
suivante. La priorité est donnée aux `non mutable policy`. Si plusieurs `non
mutable policy` sont matchées, le choix se fait par ordre
alphabétique.


Nous allons maintenant voir comment utiliser ces policy pour sécuriser son
cluster Kubernetes avec des policy par défaut.

### PSP : Best practices

Lorsque nous déployons des clusters chez nos clients, nous essayons de pousser
l'adoption de ces bonnes pratiques dès le départ, en effet il est plus
difficile d'activer les PSP sur un cluster existant que de les activer au
début d'un projet et de pousser l'adoption.

Nous allons par le suite voir les deux cas, d'une part sur un cluster
vierge et d'autre part comment activer les PSP sur un cluster existant
sans casser la compatibilité.

#### PSP par défaut

En général, on distingue deux PSP par défaut sur les clusters :

* une policy `privileged` qui autorise tout.
* une policy `default` qui autorise uniquement des fonctionnalités jugées sans
risque pour des namespaces/workloads non privilégiés.

Les resources utilisées dans la documentation Kubernetes et dans cet article sont disponibles [ici](https://github.com/therandomsecurityguy/kubernetes-security)

#### Sécuriser AWS EKS

Sur EKS, les PSP sont activées par défaut et EKS propose par défaut un mode
de compatibilité en autorisant tous les pods à utiliser une [PSP `eks-privileged`](https://github.com/aws/containers-roadmap/issues/401).

L'implementation est réalisée de la façon suivante:

Une PSP `eks.privileged` :

```yaml
apiVersion: extensions/v1beta1
kind: PodSecurityPolicy
metadata:
    seccomp.security.alpha.kubernetes.io/allowedProfileNames: '*'
  labels:
    eks.amazonaws.com/component: pod-security-policy
    kubernetes.io/cluster-service: "true"
  name: eks.privileged
spec:
  allowPrivilegeEscalation: true
  allowedCapabilities:
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
```

Un *ClusterRole* `eks:podsecuritypolicy:privileged`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    eks.amazonaws.com/component: pod-security-policy
    kubernetes.io/cluster-service: "true"
  name: eks:podsecuritypolicy:privileged
rules:
- apiGroups:
  - policy
  resourceNames:
  - eks.privileged
  resources:
  - podsecuritypolicies
  verbs:
  - use
```

Ansi qu'un *ClusterRoleBinding*:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  annotations:
    kubernetes.io/description: Allow all authenticated users to create privileged pods.
  labels:
    eks.amazonaws.com/component: pod-security-policy
    kubernetes.io/cluster-service: "true"
  name: eks:podsecuritypolicy:authenticated
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: eks:podsecuritypolicy:privileged
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:authenticated
```

Globalement cette combinaison permet à n'importe quel pod d'utiliser n'importe
quelle fonctionnalité sans restriction. C'est le comportement par défaut sur EKS.

Nous allons voir maintenant comment restreindre et sécuriser notre cluster.
L'objectif est le suivant :

1. Permettre aux noeuds ainsi qu'au namespace `kube-system` de fonctionner
correctement et de pouvoir utiliser une policy `privileged`.
2. Permettre à tous les autres namespaces d'utiliser une policy par défaut sécurisée.
3. Supprimer la politique par défaut de EKS

Nous allons créer deux PSP.

`privileged`:

```yaml
---
apiVersion: extensions/v1beta1
kind: PodSecurityPolicy
metadata:
  name: privileged
  annotations:
    seccomp.security.alpha.kubernetes.io/allowedProfileNames: '*'
spec:
  privileged: true
  allowPrivilegeEscalation: true
  allowedCapabilities: ['*']
  volumes: ['*']
  hostNetwork: true
  hostPorts:
  - min: 0
    max: 65535
  hostIPC: true
  hostPID: true
  runAsUser:
    rule: 'RunAsAny'
  seLinux:
    rule: 'RunAsAny'
  supplementalGroups:
    rule: 'RunAsAny'
  fsGroup:
    rule: 'RunAsAny'
```

`default`:

```yaml
---
apiVersion: extensions/v1beta1
kind: PodSecurityPolicy
metadata:
  name: default
  annotations:
    seccomp.security.alpha.kubernetes.io/allowedProfileNames: 'docker/default'
    seccomp.security.alpha.kubernetes.io/defaultProfileName:  'docker/default'
spec:
  privileged: false
  allowPrivilegeEscalation: false
  allowedCapabilities: []  # default set of capabilities are implicitly allowed
  volumes:
  - 'configMap'
  - 'emptyDir'
  - 'projected'
  - 'secret'
  - 'downwardAPI'
  - 'persistentVolumeClaim'
  hostNetwork: false
  hostIPC: false
  hostPID: false
  runAsUser:
    rule: 'RunAsAny'
  seLinux:
    rule: 'RunAsAny'
  supplementalGroups:
    rule: 'RunAsAny'
  fsGroup:
    rule: 'RunAsAny'
```

Ensuite nous allons autoriser les composants internes de Kubernetes ainsi que le namespace `kube-system` à utiliser la policy `privileged`.

Tout d'abord un *ClusterRole* qui match la policy `privileged` :

```yaml
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: privileged-psp
rules:
- apiGroups: ['policy']
  resources: ['podsecuritypolicies']
  verbs:     ['use']
  resourceNames: ['privileged']
- apiGroups: ['extensions']
  resources: ['podsecuritypolicies']
  verbs:     ['use']
  resourceNames: ['privileged']
```

Puis un *RoleBinding* dans le namespace `kube-system` pour autoriser l'utilisation de cette policy :

```yaml
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: privileged-psp-nodes
  namespace: kube-system
roleRef:
  kind: ClusterRole
  name: privileged-psp
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: Group
  apiGroup: rbac.authorization.k8s.io
  name: system:nodes
- kind: User
  apiGroup: rbac.authorization.k8s.io
  name: kubelet # Legacy node ID
- kind: Group
  apiGroup: rbac.authorization.k8s.io
  name: system:serviceaccounts:kube-system
```

Ces objets permettent de remplir la condition `1`.

Maintenant nous allons permettre à tous les autres ServiceAccount de tous les namespaces d'utiliser la policy `default`.

*ClusterRole* :

```yaml
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: default-psp
rules:
- apiGroups: ['policy']
  resources: ['podsecuritypolicies']
  verbs:     ['use']
  resourceNames: ['default']
- apiGroups: ['extensions']
  resources: ['podsecuritypolicies']
  verbs:     ['use']
  resourceNames: ['default']
```

*ClusterRoleBinding* :

```yaml
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: default-psp
roleRef:
  kind: ClusterRole
  name: default-psp
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: Group
  name: system:authenticated
  apiGroup: rbac.authorization.k8s.io
```

Avec ces objets, nous remplissons maintenant la conditions `2`.

Nous pouvons maintenant supprimer les resources présentes par défaut sur EKS :

```bash
kubectl --kubeconfig kubeconfig delete psp eks.privileged
kubectl --kubeconfig kubeconfig delete clusterrolebinding eks:podsecuritypolicy:authenticated
kubectl --kubeconfig kubeconfig delete clusterrole eks:podsecuritypolicy:privileged
```

Nous pouvons maintenant verifier le bon fonctionnement. Par exemple avec un
`kubectl -n kube-system get pods coredns-7ddddf5cc7-nqf4p -o yaml` sur
un des pods CoreDNS, on remarque la psp utilisée est `eks.privileged`.
En effet nous avons supprimé la policy par défaut mais
les services deja présents à ce moment là après la création du cluster
l'utilise encore.

```yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    eks.amazonaws.com/compute-type: ec2
    kubernetes.io/psp: eks.privileged
...
```

Nous allons supprimer tous les pods du namespace
`kube-system`: `kubectl -n kube-system delete pods --all`. Une fois les pods
redémarrés, vous pouvez verifier que la nouvelle PSP est bien utilisée :

```yaml
$ kubectl -n kube-system get pods coredns-7ddddf5cc7-nqf4p -o yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    eks.amazonaws.com/compute-type: ec2
    kubernetes.io/psp: privileged
```

N'importe quel pod créé dans le namespace `kube-system` pourra fonctionner de
manière privilégiée.

Nous allons maintenant tester le fonctionnement d'une workload classique.
En utilisant par exemple le namespace `default` et le cas d'un utilisateur
lambda potentiellement non trusté.

Lançons un deployment `nginx` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
```

On remarque les pods nginx se lancent sans problème, en effet le
Deployment n'a besoin d'aucun privilège particulier.

Essayons maintenant de rajouter un volume de l'host par exemple :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
        volumeMounts:
        - name: etc
          mountPath: /etc
      volumes:
      - name: etc
        hostPath:
          path: /etc
```

On remarque que rien ne se passe. Pas de rolling update, pas d'erreur, rien.
En effet, pour verifier le comportement des PSP il faut descendre au niveau
des *ReplicaSet* (gérés par les *Deployment*).

Si l'on regarde coté *ReplicaSet*, la rolling update a bien été demandée :

```bash
NAME                          DESIRED   CURRENT   READY   AGE
nginx-deployment-5c99864ddf   1         0         0       2m5s
nginx-deployment-7bfb85948d   3         3         3       4m58s
```

Regardons de plus prêt le *ReplicaSet* bloqué :

```bash
$ kubectl describe rs nginx-deployment-5c99864ddf
Name:           nginx-deployment-5c99864ddf
Namespace:      default
Selector:       app=nginx,pod-template-hash=5c99864ddf
Labels:         app=nginx
                pod-template-hash=5c99864ddf
Annotations:    deployment.kubernetes.io/desired-replicas: 3
                deployment.kubernetes.io/max-replicas: 4
                deployment.kubernetes.io/revision: 5
Controlled By:  Deployment/nginx-deployment
Replicas:       0 current / 1 desired
Pods Status:    0 Running / 0 Waiting / 0 Succeeded / 0 Failed
Pod Template:
  Labels:  app=nginx
           pod-template-hash=5c99864ddf
  Containers:
   nginx:
    Image:        nginx
    Port:         80/TCP
    Host Port:    0/TCP
    Environment:  <none>
    Mounts:
      /mount from etc (rw)
  Volumes:
   etc:
    Type:          HostPath (bare host directory volume)
    Path:          /etc
    HostPathType:
Conditions:
  Type             Status  Reason
  ----             ------  ------
  ReplicaFailure   True    FailedCreate
Events:
  Type     Reason        Age                   From                   Message
  ----     ------        ----                  ----                   -------
  Warning  FailedCreate  52s (x15 over 2m14s)  replicaset-controller  Error creating: pods "nginx-deployment-5c99864ddf-" is forbidden: unable to validate against any pod security policy: [spec.volumes[0]: Invalid value: "hostPath": hostPath volumes are not allowed to be used]
```

Le pod ne peut pas être créé car il requière un volume de l'host, ce qui n'est pas permis par le PSP `default`.

#### Activation des PSP sur un cluster générique kubeadm

Pour d'autres clusters génériques tels que des clusters déployés avec Kubeadm,
la demarche présentée pour EKS reste correcte. Dans le cas d'un cluster où les
PSP ne sont pas activées mais avec des workloads existants, prenez garde à
bien respecter les étapes dans l'ordre :

1. Création des PSP et ressources associées pour `default` et `privileged`
2. Activation des PSP dans l'API server.

En effet, il n'y a en général pas de PSP par défaut, et activer les PSP sans
les préparer en amont reviendrai à empêcher tous les pods du cluster de
démarrer faute de matcher une policy existante.

Pour activer les PSP sur l'API server, si vous utilisez un ficher de
configuration Kubeadm, vous pouvez rajouter les champs suivants :

```
apiServer:
  extraArgs:
    enable-admission-plugins: NodeRestriction,PodSecurityPolicy
```

Vous pouvez ensuite `kubeadm upgrade` votre cluster. Si vous utilisez une
méthode de déploiement autre, il faut rajouter le
flag `--enable-admission-plugins=NodeRestriction,PodSecurityPolicy` à l'API server.

### Conclusion

Je vous invite à jouer avec la policy par défaut afin de découvrir les
possibilités offerte par les PSP. L'important étant de trouver un bon
compromis entre les politiques internes de build des images Docker et les
prérequis de sécurité afin d'une part de sécuriser vos clusters Kubernetes
tout en communiquant aux développeurs les best practices de build d'images
Docker et les critères d'acceptation des images et applications sur vos clusters.

[**Kevin Lefevre**](https://www.linkedin.com/in/kevinlefevre/)
