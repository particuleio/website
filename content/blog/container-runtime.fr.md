---
Title: Le point sur les container runtimes
Date: 2018-12-17T11:00:00+00:00
Category: Kubernetes
Summary: Docker, containerd, runc, CRI, Kata Containers... faisons le point !
Author: Romain Guichard
image: images/thumbnails/kubernetes.png
lang: fr
---

Il y a trois ans, on ne parlait pas de container runtime et le seul outil connu
pour lancer et administrer des conteneurs, c'était Docker. Puis est arrivé rkt. Puis il y a eu la
guerre entre les deux, l'Open Container Initiative (OCI) a été créée et runc
est apparu.

Et maintenant on entend parler de containerd, de CRI, de CRI-O, de
Kata Containers.

Cet article va tenter de repositionner tout ce beau monde, qui remplace qui,
qui dépend de qui, de façon à avoir une bonne vision de ce que sont tous ces
outils et vous permettre de choisir les bons.

### C'est quoi une runtime ?

Si on met de côté les runtimes qui servent de contexte d'exécution pour
certains langages comme Java, dans le monde des conteneurs, la runtime est
responsable de créer et de faire fonctionner le conteneur.

Cette définition est volontairement simpliste et très générique et on verra
dans la suite de l'article qu'il existe plusieurs types de runtimes dont les
objectifs sont différents et souvent complémentaires.


### In principio erat Docker

Reconnaissons que Docker ne nous a pas simplifié la tâche pour
comprendre ce qu'était une container runtime. En effet, "à l'époque",
Docker faisait tout : il construisait des images, permettait de gérer une registry
locale, partageait des images sur le DockerHub, permettait de créer
des volumes et des réseaux et enfin démarrait des conteneurs.

Comme expliqué en introduction, rkt de CoreOS est arrivé. Deux des points
principaux mis en avant par CoreOS était la meilleure gestion de la sécurité de
par rapport à Docker et un meilleur respect de la philosophie "KISS" d'Unix.
Mais, grâce à son antériorité et à son CLI permettant
de tout faire, Docker s'est imposé. La hâche de guerre fut
enterrée à la création de l'OCI, dont le rôle fut de créer un standard
concernant la manière de démarrer un conteneur. Ce standard c'est **runc**.

Runc est en réalité la partie de Docker qui servait à créer un conteneur,
Docker n'a fait que la "donner" à l'OCI. D'où le fait que l'on considère que
Docker a gagné cette guerre contre CoreOS.

Docker a donc commencé à devenir de moins en moins monolithique. On peut
d'ailleurs voir désormais que runc est la runtime utilisée par Docker :

```bash
$ docker info | grep -i runtime
[...]
Runtimes: runc
Default Runtime: runc
```

On peut de même remarquer qu'il est possible d'avoir, a priori, plusieurs runtimes ;)

L'OCI a également standardisé autre chose, à savoir le format des images. Qui vient aussi
originellement de Docker.

[https://github.com/opencontainers/image-spec](https://github.com/opencontainers/image-spec)


### Différents types de container runtimes

Le problème a néanmoins persisté. Toutes les runtimes ne font pas la même
chose. Runc par exemple est assez bas niveau et se charge uniquement de
démarrer un conteneur, il ne prend pas en charge les activités de plus haut niveau comme gérer les
images, les pull et ne fournit pas d'API. Ce sont elles qui manipulent les
namespaces et les cgroups sur lesquels se basent les conteneurs. Un développeur
ou un sysadmin ne va que très peu intéragir avec elles, ce sont donc les
container runtimes de plus au niveau qui vont s'en charger.

En terme de technologie, runc est la container runtime la plus utilisée. Bien qu'elle soit basée sur les
travaux de Docker, elle suit en réalité la spécification de l'OCI. La version
1.0.0 de runc implémente normalement la version 1.0 de la spécification.

  - [https://github.com/opencontainers/runc](https://github.com/opencontainers/runc)
  - [https://github.com/opencontainers/runtime-spec](https://github.com/opencontainers/runtime-spec)

Rkt, présentée en introduction, en est une autre bien qu'elle fournisse aussi
des fonctionnalités de plus haut niveau.

Et nous avons donc les container runtimes de haut niveau, comme Docker. Docker
est capable de builder des images, de prendre en charge les pull, les push, etc. C'est un daemon qui
fournit une API ainsi qu'une CLI et si on a bien suivi, il délègue désormais la
partie création du conteneur à runc. Mais pas tout à fait, il existe en effet encore une couche
entre Docker et runc : containerd.

![containerd](https://containerd.io/img/logos/footer-logo.png#center)

Containerd fut aussi sortie du projet Docker. Containerd fait tout ce que
Docker fait, sauf builder une image. Nous pourrions intéragir directement avec
containerd car il fournit une CLI mais nous continuons à utiliser celle de
Docker, la force de l'habitude.

Containerd est désormais un projet de la Cloud Native Computing Foundation
(CNCF).


En conclusion, l'utilisateur interagit donc directement avec la container runtime de haut
niveau. Cette runtime est responsable généralement de pull les images, de
vérifier leur checksum, etc. Une fois ces activités de haut niveau effectuées,
elle délègue à la container runtime de bas niveau les tâches pour créer les
conteneurs.

![container runtime](https://storage.googleapis.com/static.ianlewis.org/prod/img/771/runtime-architecture.png#center)


### Kubernetes et CRI

Mais deux couches, de haut et bas niveau, ce n'était pas suffisant. Le problème
s'est posé lorsque les orchestrateurs de conteneurs sont arrivés. Je parlerai
exclusivement de Kubernetes dans cet article. Kubernetes ne crée pas lui-même
des conteneurs. Cette tâche est déléguée aux container runtimes et Kubernetes
doit donc être capable de parler à plusieurs d'entre elles, chacune ayant une API
différente. Le problème a été finalement pris dans l'autre sens, Kubernetes a
créé une interface, Container Runtime Interface (CRI), qui définit la façon
dont Kubernetes parle aux container runtimes. A elles ensuite d'implémenter ou
non les calls définis dans CRI.

Dans Kubernetes le composant responsable de la communication avec la container
runtime est le kubelet. Ce composant est installé sur tous les workers
Kubernetes. Il communique avec les container runtimes via des sockets Unix en
utilisant le framework gRPC. Le kubelet est donc le client et CRI le serveur.
Ce "serveur" est en fait une interface shim qui intercepte et traduit les calls
entre le kubelet et la container runtime.

![kubelet](https://d3vv6lp55qjaqc.cloudfront.net/items/0I3X2U0S0W3r1D1z2O0Q/Image%202016-12-19%20at%2017.13.16.png#center)

CRI-O est un autre exemple de runtime qui implémente CRI et communique ensuite
avec une autre runtime qui implémente elle la spécification de l'OCI. CRI-O peut, par
exemple, parler à runc ou à Kata Containers.

![katacontainers](https://katacontainers.io/images/kata-explained1@2x.png#center)

[Plus d'infos sur Kata Containers](https://katacontainers.io/posts/why-kata-containers-doesnt-replace-kubernetes/)


#### Implication pour vos clusters Kubernetes

Une implication directe de ces informations est que Docker n'est pas un
prérequis à Kubernetes et ne peux même pas être considéré comme un choix par
défaut. La version 1.0.0 de containerd est sortie en décembre 2017 et est prête
pour la production. Docker et Kubernetes est donc un choix qui se justifie
historiquement, au delà, la compétitivité avec les autres runtimes est réelle.

[Cet article de mai 2018 explique comment s'affranchir de Docker avec Kubernetes](https://kubernetes.io/blog/2018/05/24/kubernetes-containerd-integration-goes-ga/)

Si vous êtes à l'aise avec la CLI Docker, rien ne vous empêche de continuer à
l'utiliser, seulement Docker ne sera plus qu'utilisé vous, pas par Kubernetes.
Est-ce donc réellement utile ?

Néanmoins, un point reste à éclaircir quand on souhaite se débarrasser de
Docker au sein de Kubernetes : **le build d'image**. En effet, containerd ne
sait pas builder d'images. Fort heureusement il existe plusieurs projets visant
à solutionner ce problème, ces liens vous donneront de quoi réfléchir :

- [img](https://github.com/jessfraz/img)
- [buildah](https://github.com/containers/buildah)
- [Kaniko](https://github.com/GoogleContainerTools/kaniko)


Voilà pour ce tour d'horizon des container runtimes, certaines technologies ont
volontairement été omises, nous aurions pu citer
[gVisor](https://github.com/google/gvisor),
[frakti](https://github.com/kubernetes/frakti) ou
[Railcar](https://github.com/oracle/railcar)


**Romain Guichard - [@herrguichard](https://twitter.com/herrguichard)**
