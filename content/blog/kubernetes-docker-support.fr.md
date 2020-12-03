---
Title: Kubernetes ne supporte plus Docker. Voici pourquoi ce n'est pas grave.
Date: 2020-12-03
Category: Kubernetes
Summary: Kubernetes stop le support de Docker à partir de la version 1.20, voici pourquoi ce n'est absolument pas grave et même une bonne chose
Author: Romain Guichard
image: images/thumbnails/kubernetes.png
imgSocialNetwork: images/og/kubernetes-docker-support.png
lang: fr
---


[C'est l'info du jour qui fait trembler tout le monde : Kubernetes va déprécier
le support de Docker](https://github.com/kubernetes/kubernetes/pull/94624)
à partir de la version `1.20` dont la sortie est prévue
dans quelques jours/semaines.

Catastrophe.

Ou pas.

Revenons tout d'abord sur ce qu'est Docker et sur sa relation avec Kubernetes.


# Docker, le mauvais élève des container runtimes

Docker est une stack technologique fournissant plusieurs mécanismes pour faire
fonctionner vos conteneurs. Il permet de construire des images, de créer des
volumes, de créer des réseaux, de démarrer des conteneurs et grâce à son
intégration avec Swarm, permet de se transformer en orchestrateur et de gérer
des clusters d'hôtes Docker.

Kubernetes en revanche est simplement un orchestrateur de conteneurs. Il ne
build pas d'image, ne crée pas de réseau, ne crée pas de volume et ne démarre
même pas de conteneurs. Pour toutes ces actions, Kubernetes a défini des
interfaces permettant à n'importe quel logiciel tiers d'effectuer ces actions à
sa place. Ces interfaces sont actuellement au nombre de trois :

- [Container Runtime Interface (CRI)](https://github.com/kubernetes/cri-api)
- [Container Network Interface
  (CNI)](https://github.com/containernetworking/cni)
- [Container Storage Interface
  (CSI)](https://github.com/container-storage-interface/)

Ces interfaces vous permettent d'utiliser Weave, Calico ou Cilium comme plugin
réseau, car ces solutions sont compatibles avec CNI. Elles vous permettent
d'utiliser Ceph, AWS EBS ou OpenStack Manila comme backend pour vos Persistent
Volumes car ces solutions sont compatibles avec CSI. Kubernetes n'a donc pas
besoin que ces fonctions soient supportées par Docker, Kubernetes n'a besoin
que d'une seule chose de la part de Docker : être une **container runtime**. Et
malheureusement Docker n'est pas compatible avec CRI, on doit utiliser un
composant appelé **dockershim** pour faire travailler Docker et Kubernetes
ensemble. Ce n'est pas grave en soit, mais c'est un développement spécifique à
prévoir uniquement pour faire fonctionner Docker, alors que des implémentations
compatibles existent. C'est le support de ce composant qui est en réalité
arrêté.

Revenons sur ce qu'est une container runtime. [Vous pouvez aussi retrouver notre
article](https://particule.io/blog/container-runtime/).

# Les container runtimes

Une container runtime est le composant logiciel chargé de créer les conteneurs,
c'est à dire de manipuler les namespaces et les cgroups du Kernel Linux. Afin
d'abstraire la complexité de gérer le Kernel, les container runtimes exposent
des interfaces ou des API pour permettre aux humains de les manipuler
facilement. C'est en partie ce que fait Docker via sa CLI et son API, mais
Docker fait bien plus que
ça comme nous venons de le voir. Et dans le cas de Kubernetes ça ne nous est pas
vraiment utile.

Pis, Docker est en réalité une container runtime de haut niveau et ce n'est pas
lui qui s'occupe de créer les conteneurs, il délaisse cette tâche à une
container runtime de plus bas niveau que lui :
[**containerd**](https://containerd.io/), projet graduated de la
[CNCF](https://www.cncf.io/).

Et on peut même aller encore plus loin, containerd délègue aussi cette tâche à
**runc**, l'implémentation officielle de [l'OCI](https://opencontainers.org/).

![](https://insujang.github.io/assets/images/191031/cri-containerd.png)

# Kubernetes != Docker

L'hégémonie de Docker il y a quelques années a crée un dangereux parallèle
entre "conteneurs" et "Docker". Par la suite on a donc tout naturellement
associé Kubernetes et Docker puisque comme Kubernetes orchestre des conteneurs
et que `conteneur = docker`...

Comme vu précédemment, Kubernetes utilise l'interface CRI qui lui permet de
s'interfacer avec n'importe quelle container runtime supportant CRI et ces
container runtimes sont nombreuses, chacune avec ses propres spécificités
évidemment :

- [containerd](https://containerd.io/)
- [CRI-O](https://cri-o.io/)
- [kata containers](https://katacontainers.io/)
- [falco](https://falco.org/)
- [firecracker](https://firecracker-microvm.github.io/)
- [gVisor](https://github.com/google/gvisor)

![](/images/container-runtime-logo.png)
Vos clusters Kubernetes sont donc sains et saufs, il suffit d'utiliser
n'importe laquelle de ces container runtimes pour vous passer de Docker.
Containerd est évidemment un candidat tout trouvé puisque il fonctionne déjà
sous Docker et vous ne devriez voir aucun changement de comportement.

Notre outil [Symplegma](https://github.com/particuleio/symplegma) utilise
depuis le début de son existence Containerd comme container runtime, Docker
n'est jamais installé.

# Et mes images Docker, il faudra tout reconstruire ?

Et non. Les "images Docker" n'en sont pas en réalité, il s'agit d'un abus de
langage pour parler d'images OCI. L'OCI est un organisme qui gère deux
spécifications, celle définissant comment un conteneur doit être crée (dont
l'implémentation est runc si vous avez suivi ;) ) et celle
définissant comme une image est construite. Docker supporte ces deux
spécifications et vos images construites avec Docker fonctionneront sans
sourciller avec n'importe quelle container runtime.

# Comment je mets mes clusters à jour ?

Tout d'abord, il faut savoir que chaque node Kubernetes peut utiliser sa propre
container runtime car celle ci se configure au niveau du Kubelet. Vous pouvez
donc procéder à une mise à jour node par node sans avoir à réinstaller
l'intégralité de votre cluster Kubernetes. La procédure consiste à vider
votre node de ses pods, d'installer une nouvelle container runtime puis de
reconfigurer le Kubelet avec cette nouvelle container runtime et de le
redémarrer. Votre node est prêt.


Les ingénieurs Particule sont tous certifiés Kubernetes et sauront vous aider à
mettre en place cette transition. N'hésitez pas à prendre contact pour en
discuter !





**Romain Guichard - [@herrguichard](https://twitter.com/herrguichard)**
