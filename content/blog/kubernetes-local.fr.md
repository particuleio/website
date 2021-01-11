---
Title: "Travailler avec Kubernetes en local"
Date: 2021-01-11
Category: Kubernetes
Summary: "De nombreux outils permettent de travailler avec Kubernetes
en local sur son poste de travail, ces solutions sont intéressantes à
plusieurs niveaux"
Author: Romain Guichard
image: images/thumbnails/kubernetes.png
imgSocialNetwork: images/og/kubernetes-local.png
lang: fr
---

Comment travailler avec Kubernetes ? De quoi a t-on besoin ? Ce sont des
questions qui reviennent régulièrement et pour cause, lorsqu'on étudie
Kubernetes et son fonctionnement, on tombe rapidement sur des configurations
matérielles ou virtuelles relativement complexes. Le cluster etcd peut être
installé sur les mêmes nodes hébergeant l'api-server et les autres éléments du
control plane. Le control plane peut être constitué de un ou plusieurs nodes en
fonction du niveau de résilience souhaité. Pareil pour etcd. De multiples
configurations sont possibles et chacune a ses avantages et ses inconvénients.
Une fois que cette configuration est choisie, la seconde question que l'on se
pose est bien souvent "où ?". En effet, l'endroit où sera déployé Kubernetes
est un choix important puisque certaines fonctions (Service loadbalancer,
Storage Class, etc) ne seront peut-être pas disponibles.

Lorsqu'on souhaite déployer Kubernetes afin de s'entrainer, expérimenter,
tester Kubernetes, cela fait beaucoup de questions sans réponse.

Nous vous proposons un aperçu des possibilités qui s'offrent à vous pour
déployer Kubernetes en local sur votre poste de travail sans compromis sur les
fonctionnalités.

## La bonne recette

Lorsqu'on souhaite travailler sur Kubernetes en local, on cherche tout d'abord
la simplicité. On ne souhaite pas passer plusieurs heures à prendre en main des
outils comme [Kubespray](https://kubespray.io) pour déployer Kubernetes.
Particule a développé une version "plus légère" de Kubespray,
[Symplegma](https://github.com/particuleio/symplegma) mais même ça c'est encore
trop lourd. On souhaite quelque chose de simple à utiliser, qui puisse démarrer
et supprimer un cluster Kubernetes en quelques minutes. On veut aussi avoir
accès à l'ensemble de l'API, pas à un subset et à la possibilité d'utiliser
toutes les fonctionnalités comme si on était sur un cluster de production.

En terme d'architecture, c'est simple on veut généralement un seul node, qui
fera office de control plane et de worker. On souhaiterai néanmoins avoir le
choix de faire du multi-nodes si l'envie nous en prenait. Pour tester des
fonctions de schéduling ou de communication inter-nodes, c'est plutôt utile.

## Kubeadm : le projet officiel

![kubeadm](https://raw.githubusercontent.com/kubernetes/kubeadm/master/logos/stacked/color/kubeadm-stacked-color.png#logosize)

[Kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
 (à prononcer kube admin et non pas kubeADM) est le projet officiel
de Kubernetes permettant de bootstraper un cluster. Kubeadm se compose d'un
binaire incluant une ligne de commande assez complète. Kubeadm est utilisé par
un nombre important de projet tiers comme la solution pour bootstraper un
cluster Kubernetes. Mais c'est là sa limite, il ne fait que ça. En soit pour
démarrer un control plane Kubernetes, il suffit de :

```
$ kubeadm init
```

Mais pour bénéficier en sortie d'un control plane fonctionnel, cela
présuppose que plusieurs choses soient installées, en amont ou en aval :

- [une container runtime](https://particule.io/blog/container-runtime/)
- kubelet
- un plugin CNI
- plusieurs paquets de la distribution

Kubeadm peut être configuré via sa ligne de commande ou en y passant un fichier
de configuration :

```
---
apiVersion: kubeadm.k8s.io/v1beta1
kind: ClusterConfiguration
kubernetesVersion: v1.20.0
metadata:
  name: 1.20-sample
apiServer:
  extraArgs:
    advertise-address: 192.168.0.103
    anonymous-auth: false
    enable-admission-plugins: AlwaysPullImages,DefaultStorageClass
    audit-log-path: /home/johndoe/audit.log
```

Si vous souhaitez ajouter des nodes à votre cluster, il faudra démarrer une
nouvelle machine virtuelle (ou physique), refaire le processus d'installation
"pre-kubeadm" puis utiliser `kubeadm join` pour l'ajouter à votre cluster.

Kubeadm est donc un bon outil quand il est accompagné d'une surcouche comme
[kops](https://github.com/kubernetes/kops),
[kubespray](https://kubespray.io/#/) ou
[symplegma](https://github.com/particuleio/symplegma) mais il **ne convient
pas** à utilisation de test rapide sur un poste de travail.

## Minikube, l'ancien

![](https://raw.githubusercontent.com/kubernetes/minikube/master/images/logo/logo.png#logosize)

[Minikube](https://minikube.sigs.k8s.io) fut probablement le premier outil pour installer rapidement et
facilement Kubernetes. Projet officiel Kubernetes, Minikube a l'énorme avantage
aujourd'hui de pouvoir déployer Kubernetes de différentes besoins grâce à ses
drivers. Le moyen le plus commun est de déployer Kubernetes dans des VM
VirtualBox mais Minikube possède des drivers pour :

- Docker
- VMware
- Hyper-V
- KVM
- podman
- etc

Grâce à ses plugins, Minikube permet automatiquement d'installer un Ingress
Controller ou d'activer le Dashboard Kubernetes. Minikube possède aussi un mode
["LoadBalancer"](https://minikube.sigs.k8s.io/docs/handbook/accessing/#loadbalancer-access)
pour permettre d'utiliser ce type de Service en dehors d'un cloud public.

## Kind : Kubernetes in Docker

![kind](https://d33wubrfki0l68.cloudfront.net/d0c94836ab5b896f29728f3c4798054539303799/9f948/logo/logo.png#logosize)

[Kind](https://kind.sigs.k8s.io/) est un outil de déploiement de Kubernetes
géré par le Sig Testing et hébergé sous
[kubernetes-sigs](https://github.com/kubernetes-sigs/kind/). Kind permet de
déployer des clusters Kubernetes en se servant de conteneurs Docker comme des
nodes Kubernetes. Chaque node utilise kubeadm afin de bootstraper le cluster ou
de rejoindre un cluster existant.

Malgré [l'arrêt du support de Docker par
Kubernetes](https://particule.io/blog/kubernetes-docker-support/), Kind utilise
Docker ou Podman
pour bootstraper les clusters mais il s'agit bien d'une runtime compatible CRI,
containerd, qui est utilisée à l'intérieur des clusters. Dockershim n'est pas
utilisé.

Les clusters Kind peuvent être configurés au moyen d'un fichier YAML, comme
kubeadm.

```yaml
# Un node control-plane et deux nodes workers
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker

---

# trois nodes control-plane et trois nodes workers
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: control-plane
- role: control-plane
- role: worker
- role: worker
- role: worker
```

Il ne reste qu'à charger ce fichier au boot du cluster.

```
$ kind create cluster --config config.yaml --name cluster
```

Des contexts `kind-${cluster_name}` sont crées dans votre kubeconfig afin d'y
accéder.

Une Storage Class "locale" est inclue permettant d'utiliser le stockage local de
votre machine grâce à l'image `rancher/local-path-provisioner`

## k3s, k8s moins 5

![k3s](https://pbs.twimg.com/media/EbxmIvqWkAEbDKG.jpg#logosize)

Nous avons déjà abordé le cas de k3s dans un [précédent
article](https://particule.io/blog/k3s/). K3s est un produit développé par
Rancher.

k3s se compose d'un binaire d'une cinquantaine de Mo. Il suffit de le lancer pour
bénéficier d'un cluster Kubernetes up and running.

```
$ k3s kubectl get node
NAME           STATUS   ROLES                  AGE    VERSION
rguichard-x1   Ready    control-plane,master   345d   v1.20.0+k3s2
```

Sont inclus :

- [Traefik](https://doc.traefik.io/traefik/)
- metrics-server
- flannel
- [klipper-lb](https://github.com/k3s-io/klipper-lb)
- Local path provisioner

Ces deux derniers éléments permettent de disposer du type `loadbalancer` pour
les Services ainsi que d'une StorageClass fonctionelle utilisant le stockage
local de votre machine. Ces deux éléments font partis des pain points
rencontrés par la plupart des équipes ayant tenté l'aventure de Kubernetes en
dehors d'un cloud public.

Nous avons d'ailleurs rédigé [un article à ce
sujet](https://particule.io/en/blog/k8s-no-cloud/).

### Aller encore plus loin avec k3d

![k3d](https://raw.githubusercontent.com/rancher/k3d/main/docs/static/img/k3d_logo_black_blue.png#logosize)

k3s ne permet de disposer que d'un seul control plane ce qui peut être
problématique dans le cas de tests en parallèle.

Pour cela Rancher dispose d'un deuxième produit :
[k3d](https://github.com/rancher/k3d) qui permet de piloter k3s et de déployer
les clusters dans des conteneurs Docker.

```
$ k3d cluster create first --agents 3
$ k3d cluster create second --servers 3
$ k3d cluster create third --agents 3 --servers 3
$ k3d cluster list
NAME          SERVERS   AGENTS   LOADBALANCER
first         1/1       3/3      true
second        3/3       1/1      true
third         3/3       3/3      true
```

k3d permet de choisir le nombre de node du control plane et le nombre de worker
que vous souhaitez.

Des contexts `k3d-${cluster_name}` sont automatiquement crées dans
`~/.kube/config` afin de pouvoir vous y connecter avec vos outils habituels.


```
$ kubectl get node
NAME                 STATUS   ROLES         AGE   VERSION
k3d-third-agent-0    Ready    <none>        12s   v1.19.4+k3s1
k3d-third-agent-1    Ready    <none>        11s   v1.19.4+k3s1
k3d-third-agent-2    Ready    <none>        10s   v1.19.4+k3s1
k3d-third-server-0   Ready    etcd,master   50s   v1.19.4+k3s1
k3d-third-server-1   Ready    etcd,master   36s   v1.19.4+k3s1
k3d-third-server-2   Ready    etcd,master   17s   v1.19.4+k3s1
```

## Et les autres ?

D'autres solutions existent évidemment, nous avons choisi de ne pas les
aborder car être exhaustif est voué à l'échec. On peut néanmoins citer [MicroK8s](https://microk8s.io/)
(Ubuntu) et [k0s](https://k0sproject.io/) (Mirantis) qui sont d'excellents produits et auraient eu leur
place ici.


Pour vos projets Kubernetes, qu'ils soient mono ou multi tenants, on premises ou
sur un Cloud public, [n'hesitez pas à nous contacter](mailto:contact@particule.io)

L'équipe [Particule](https://particule.io)
