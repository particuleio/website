---
Title: Continuous delivery avec Weave Flux et Concourse-CI
Date: 2019-06-26T11:00:00+02:00
Category: Kubernetes
Summary: GitOps avec Concourse comme CI et Flux comme CD !
Author: Romain Guichard
image: images/thumbnails/weave.png
imgSocialNetwork: images/og/concourse-fluxcd.png
lang: fr
---

Nous en avons déjà parlé sur ce blog, DevOps ne désigne pas une série d'outils
mais bien des pratiques de travail que certains outils, en effet, aident à
mettre en place. Dans le même ordre d'idée, il n'y a pas d'outils **GitOps**
mais bien une série de pratiques et de principes qui peuvent être mis en
application par différents outils. Pour l'histoire, le terme **GitOps** sort
tout droit de chez Weave, les créateurs du plugin CNI Weave ainsi que de
Flagger, un opérateur Kubernetes de contiuous delivery.

### GitOps ?

Pour expliquer la problématique que GitOps tente de résoudre, revenons un peu
en arrière et parlons d'Infrastructure as Code. Ce concept désigne le fait de
décrire, de manière **déclarative**, dans des fichiers texte notre infrastructure. Les avantages sont
nombreux :

- lisibilité
- versionnement dans Git

Grâce à Git, nous sommes capables de rapidement revenir à un état antérieur
(**git revert**), d'effectuer un différentiel entre deux versions
(**git diff**), d'agresser votre collègue ayant commis une erreur (**git
blame**) !!

Git devient notre **single source of truth** et permet d'obtenir une
reproductibilité quasiment parfaite. Bien entendu, votre infrastructure n'est
pas la seule concernée, tout peut, et **doit** finir dans votre Git :
configuration, dashboards, monitoring etc. Grâce à des outils comme les Pull
Requests de GitHub, vous êtes en mesure de contrôler les modifications
apportées à votre code.

Ce sont là trois des quatre principes de GitOps :

- Votre système est déclarativement décrit
- L'état désiré de votre système est stocké dans Git
- Les changements sont contrôlés et appliqués dès leur validation


Mais qu'est-ce que GitOps apporte de plus ? Et bien des tas de choses. Les
premiers bénéfices viennent évidemment de Git. Il devient le seul outil que vos
développeurs ont besoin de connaître, il permet d'obtenir un historique clair
des modifications effectuées et ses capacités de revert/rollback permettent de
contrôler facilement, a posteriori, des modifications. GitOps s'applique aussi
bien à vos applications qu'à votre infrastructure, vous n'avez donc plus qu'un
seul workflow pour déployer en production. Finalement ce que vous developpez ce
ne sont pas des conteneurs, c'est du code.

La quatrième principe est qu'une fois l'état désiré déployé, un système doit se
charger de contrôler que cet état est maintenu et que le système déployé ne
dérive pas de la source de vérité.

### Et dans le détail alors ?

GitOps va donc se comporter comme une interface entre votre code et vos
applications/infrastructures/conteneurs. Vous n'intéragissez qu'avec Git, vous
utilisez un système de review (Gerrit, PR, MR, etc) pour soumettre des
modifications sur votre infrastructure. Vous utilisez les fonctions natives de Git pour
effectuer un _rolling update_ ou un _rollback_. Tout est standard, vous n'avez pas
à connaître les subtilités de chacune des CLI (kubectl, ctr, awscli, openstack-cli,
etc) nécessaires à votre projet. Avec GitOps il y a une claire séparation entre
la déclaration de votre système et la manière dont cet état est appliqué.

[Weave Flux](https://github.com/weaveworks/flux) s'occupe des fonctions principales :

 - Synchronisation du contenu d'un dépôt Git avec votre cluster
 - Déploiement automatique de nouvelles images Docker

![flux-workflow](https://github.com/fluxcd/flux/raw/master/docs/_files/flux-cd-diagram.png)

Quant à Concourse-CI, [nous en avons déjà parlé dans un précédent article](https://particule.io/blog/k8s-concourse-cd/).
Dans cet article, nous avons mis une chaîne de CI/CD complète jusqu'au
déploiement sur Kubernetes. Nous allons reproduire le même type de workflow
mais en déléguant la partie "CD" à Flux. Concourse-CI se chargera donc
uniquement de builder nos images à chaque nouveau commit.

Tout ça est en réalité très simple, mais terriblement puissant.

### Mise en pratique

#### Use case

Nous allons utiliser une application toute simple, une page web avec un Hello
World. Concourse-CI va se charger de builder notre application puis Flux se chargera
continuellement de la déployer sur notre cluster Kubernetes. Nous changerons le
code de cette application et observerons le résultat.

#### Préparation

##### Notre application

Je vais utiliser cette application :
<https://github.com/particuleio/demo-concourse-flux>

L'application est composée d'un fichier index.php et d'une image PNG. Le
Dockerfile servant à builder l'application se trouve à la racine et j'ai crée
un dossier "deploy" dans lequel se trouvent [les déclarations de ressources
Kubernetes](https://github.com/particuleio/demo-concourse-flux/blob/master/deploy/helloworld.yml).
Le cluster Kubernetes sur lequel sera déployée l'application est en 1.15.

##### Mise en place de Concourse

![concourse-logo](/images/concourse-logo.png#center)

Le guide d'installation est disponible [ici](https://concourse-ci.org/install.html).
On ne rentre pas dans le détail ici, il n'y a rien de spécial à connaître ou à
effectuer côté Concourse.

##### Mise en place de Flux

<https://github.com/weaveworks/flux/blob/master/site/get-started.md>

Tout se déploie naturellement directement sur Kubernetes :

```bash
git clone https://github.com/weaveworks/flux
cd flux/
```

Un seul fichier a besoin d'être édité : `deploy/flux-deployment.yaml`

```bash
- --git-url=ssh://git@github.com/particuleio/demo-concourse-flux
- --git-branch=master
- --git-path=deploy
```

- `--git-url` spécifie le dépôt git qui sera surveillé par Flux. Pensez à
récupérer la clé publique de votre Flux et à l'installer dans les _Deploy Keys_
de votre projet sur Github. Oui, seul un dépôt peut être surveillé à la fois.
- `--git-branch`, je pense que c'est assez clair.
- `--git-path` précise les chemins dans votre dépôt qui seront effectivement
  surveillés. Dans notre cas, nous avons mis le fichier des ressources Kubernetes
  dans un dossier "deploy".

Flux n'impose aucune hiérarchie, `--git-path` permet justement de vous donner la
possibilité de choisir la votre si vous le souhaitez.

Une fois que c'est prêt : `kubectl apply -f deploy/`

#### Création du Pipeline

```yaml
resources:
  - name: git
    type: git
    source:
      uri: https://github.com/particuleio/demo-concourse-flux
      branch: master
  - name: version
    type: semver
    source:
      driver: git
      uri: git@github.com:particuleio/demo-concourse-flux
      branch: version
      file: version
      private_key: {{rguichard_pkey}}
  - name: image-helloworld
    type: docker-image
    source:
      repository: particule/demo-concourse-flux
      username: rguichard
      password: {{dh-rguichard-passwd}}
jobs:
  - name: "Docker Build"
    public: false
    plan:
      - get: version
        params:
          bump: patch
      - get: git
        trigger: true
      - put: image-helloworld
        params:
          build: git
          tag_file: version/version
      - put: version
        params:
          file: version/version
```

Afin de suivre les versions de notre application, nous utilisons [la ressource
`semver`](https://github.com/concourse/semver-resource). Cette ressource a besoin d'un backend pour stocker ce numéro de
version. Nous avons fait le choix simple de stocker cette version dans le même
dépôt que l'application, mais dans une branche séparée. Nous aurions pu la
stocker dans un bucket S3, ce qui parait plus propre. Notons que nous
choisissons, question de simplicité, d'effectuer des patchs (le z de x.y.z de
semver), à retenir pour la configuration de Flux ;)

Le reste du pipeline est plutôt simple, vous pourriez reproduire la même chose
avec n'importe quelle CI assez facilement.


#### Configuration Flux

La majeure partie du travail a déjà été effectué en réalité. Il nous reste
seulement à ajouter quelques annotations à notre deployment pour préciser à
Flux le comportement que nous souhaitons obtenir.

```yaml
flux.weave.works/automated: "true"
flux.weave.works/tag.helloworld: semver:~1.0
```

- `automated`, active flux, logique.

La seconde ligne est la plus importante. Elle permet, pour le conteneur
"helloworld" de suivre semver pour les versions de ses images. Nous précisons
même que la version Semver doit matcher une 1.0. Seuls les patchs de la 1.0
seront donc pris en compte par Flux pour mettre à jour notre image.


On peut donc lancer tout ça !

Pour Concourse, cela se passe avec la CLI
[Fly](https://concourse-ci.org/setting-pipelines.html), pour Flux normalement
vous n'avez rien à faire puisqu'il a déjà commencé à surveiller votre dépot git

![concourse](/images/concourse-flux-1.png)

![concourse](/images/concourse-flux-2.png)

```
ts=2019-06-26T16:49:23.845635134Z caller=daemon.go:652 component=daemon event="**Automated release of particule/demo-concourse-flux:1.0.1**" logupstream=false
```

Une fois que tout s'est déroulé correctement on peut constater plusieurs choses
:

- Notre application répond bien sur la règle Ingress spécifiée
- Un nouveau tag est apparu sur notre image Docker
- Le contenu du fichier `version` de la branche `version` a changé (bump)
- Flux a commité le changement de version de notre application (git log)


Et là c'est le drame.

Puisque Flux a commit dans notre répo, cela a déclenché la CI. Et on est
reparti pour un tour. Fort heureusement, Flux a un moyen de prévenir cela. Il
faut retourner dans la configuration et y ajouter `--git-ci-skip`. Cela pour
effet d'ajouter *[ci skip]* au message commit et de faire comprendre à la quasi
totalité des CI de ne pas lancer un nouveau build.

### Et GitOps dans tout ça ?

Et bien on y est. Si vous avez des changements à faire, ceux ci ne passeront
qu'au travers d'un commit ou d'une PR sur le dépot
<https://github.com/particuleio/demo-concourse-flux>. Vous pouvez vous amusez à
changer la couleur du texte et à voir Concourse builder votre nouvelle image
puis Flux la déployer et synchroniser l'état de l'application sur le cluster
Kubernetes avec la déclaration du `deployment` dans Git.

Et si vous souhaitez changer la définition de votre Ingress, vous pouvez commit
ces changements et voir Flux (Concourse n'intervient pas ici) mettre à jour
votre Ingress sur votre cluster sans que vous ayez à vous connecter à votre
cluster et lancer un `kubectl apply`.



**Romain Guichard - [@herrguichard](https://twitter.com/herrguichard)**
