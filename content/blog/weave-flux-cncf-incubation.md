---
Title: Weave Flux intègre la Sandbox de la CNCF !
Date: 2019-07-25
Category: Kubernetes
Summary: Weave Flux intègre la Sandbox, le premier stade du "Graduate program" de la CNCF
Author: Romain Guichard
image: images/thumbnails/weave.png
lang: fr
---

Ce n'est pas l'info de l'année, mais je souhaitais néanmoins le faire
remarquer, **[Weave Flux](https://github.com/fluxcd/flux) vient d'être accepté dans la Sandbox de la CNCF**. Nous
avons justement parlé de Flux sur ce blog le mois
dernier avec [un article montrant une chaine d'intégration et de déploiement
continue sur Kubernetes en utilisant Concourse-CI et Flux
!](https://blog.alterway.fr/continuous-delivery-avec-weave-flux-et-concourse-ci.html)

Profitons-en pour parler de la CNCF et de cette Sandbox et de ce que cela
signifie pour Flux.

# Les fondations Open Sources

La plupart des projets Open Source sont aujourd'hui chapotés par des
fondations, cela permet à ces projets de garder une certaine indépendance
vis-à-vis de leur créateur d'origine, d'être neutre et donc d'attirer des
développeurs d'horizons différents. Ces fondations ont aussi un rôle
"marketing", elles possèdent généralement les trademarks sur les logos et les
noms, organisent les conférences aux quatre coins du monde, fédèrent les user
groups locaux et promeuvent les différents projets pour les faire gagner en
visibilité. Chaque fondation est différente et peut avoir des attributions en
moins ou en plus évidemment.

On peut noter :

- [La Linux Foundation](https://www.linuxfoundation.org/) qui s'occupe notamment du Kernel Linux mais qui chapote
  surtout d'autres fondations
- L'[OpenStack Foundation](https://www.openstack.org/foundation/) qui gère OpenStack mais aussi Kata Containers et Zuul
  par exemple
- La [Cloud Native Computing Foundation (CNCF)](https://www.cncf.io/) qui se trouve sous la Linux
  Foundation et s'occupe de Kubernetes mais aussi de Prometheus, containerd,
  CNI, Helm etc.


# Les différents niveaux de projets de la CNCF

La CNCF héberge donc un nombre assez important de projets, 40 à l'heure où
j'écris ces lignes, mais ces projets ne sont pas tous égaux et sont répartis en
3 classes :

- Graduated
- Incubating
- Sandbox

![cncfprogram](/images/cncf/graduate-program.png)

Ces différents niveaux marquent des différence en terme de maturité et servent
d'indicateurs aux utilisateurs pour leur permettre de faire un choix éclairé.

Le Technical Oversight Commitee est responsable de juger et de décider de ce
niveau de maturité et de permettre à des projets de passer au niveau supérieur.
Pour cela, différents éléments sont pris en compte :

- Nombre d'utilisateurs
- Stabilité du code (on ne parle pas ici d'être exempts de bugs, on parle d'un
  code qui ne change pas toutes les 5 min)
- Contributeurs venant de différentes organisations
- Respecter les best practices de la CNCF

6 projets seulement sont actuellement dans le dernier niveau "Graduated" de la
CNCF !

![graduatedprogram](/images/cncf/graduated.png)

Tous les détails peuvent être trouvés ici :
<https://github.com/cncf/toc/blob/master/process/graduation_criteria.adoc>


## La Sandbox pour Flux

Flux intègre donc le premier niveau : la Sandbox. Cela va lui permettre de
gagner en visibilité, d'augmenter son nombre d'utilisateurs, ce qui entrainera
plus de remontées de bugs, plus de contributions et finalement contribuera à en
faire un projet plus stable dans le temps !

**[Romain Guichard](https://www.linkedin.com/in/romainguichard/)**
