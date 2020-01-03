---
Title: Continuous delivery avec Weave Flux et Concourse-CI
Date: 2019-06-26T11:00:00+02:00
Category: Kubernetes
Summary: GitOps avec Concourse comme CI et Flux comme CD !
Author: Romain Guichard
image: images/thumbnails/weave.png
lang: fr
---

Nous en avons déjà parlé sur ce blog, DevOps ne désigne pas une série d'outils
mais bien des pratiques de travail que certains outils, en effet, aident à
mettre en place. Dans le même ordre d'idée, le terme *GitOps* commence très
sérieusement à émerger.

# GitOps ?

Pour expliquer la problématique que GitOps tente de résoudre, revenons un peu
en arrière et parlons d'Infrastructure as Code. Ce concept désigne le fait de
décrire dans des fichiers texte notre infrastructure. Les avantages sont
nombreux :

- lisibilité
- versionnement dans Git

Grâce à Git, nous sommes capables de rapidement revenir à un état antérieur
(**git revert**), d'effectuer un différentiel entre deux versions
(**git diff**), d'agresser votre collègue ayant commis une erreur (**git
blame**) !!

Git devient notre **single source of truth** et permet d'obtenir une
reproductibilité quasiment parfaite. L'idempotence, elle, dépend de l'outil
utilisé et de la qualité de votre code. Certains modules Ansible par exemple
vous indiqueront toujours un **changed** bien qu'aucun changement n'ait lieu.
Bien entendu, votre infrastructure n'est pas la seule concernée, tout peut, et
*doit* finir dans votre Git : configuration, dashboards, monitoring etc.


Mais qu'est-ce que GitOps apporte de plus ? Et bien dans le cas que nous avons
décrit, nous avons une seule source de vérité mais nous n'avons aucun moyen de
nous assurer que ce qui est décrit dans nos fichiers texte est ce qui réellement
déployé. Nous nous basons sur ces fichiers pour créer notre infrastructure mais
nous utilisons directement les API de notre cloud provider pour déployer. Nous
déployons donc directement des conteneurs (parce que 2019). Avec GitOps, ce ne
sont pas des conteneurs, mais du code qui est déployé, différence subtile mais
pas insignifiante.

# Et dans le détail alors ?

GitOps va donc se comporter comme une interface entre votre code et vos
applications/infrastructures/conteneurs. Vous n'intéragissez qu'avec Git, vous
utilisez un système de review (Gerrit, PR, MR, etc) pour soumettre des
modifications sur votre infrastructure. Vous utilisez les fonctions natives de Git pour
effectuer un _rolling update_ ou un _rollback_. Tout est standard, vous n'avez pas
à connaitre les subtilités de chacunes des CLI (kubectl, ctr, awscli, openstack-cli,
etc) nécessaires à votre projet.

[Weave Flux](https://github.com/weaveworks/flux) s'occupe des fonctions principales :

 - Synchronisation du contenu d'un dépôt Git avec votre cluster
 - Déploiement automatique de nouvelles images Docker

![flux-workflow](https://raw.githubusercontent.com/weaveworks/flux/master/site//images/deployment-pipeline.png)

Quant à Concourse-CI, [nous en avons déjà parlé dans un précédent article](https://blog.alterway.fr/construire-un-pipeline-de-deploiement-continu-avec-kubernetes-et-concourse-ci.html).
Dans cet article, nous avons mis une chaine de CI/CD complète jusqu'au
déploiement sur Kubernetes. Nous allons reproduire le même type de workflow
mais en déléguant la partie "CD" à Flux. Concourse-CI se chargera donc
uniquement de builder nos images à chaque nouveau commit.

Tout ça est en réalité très simple, mais terriblement puissant.

# Mise en pratique

## Use case

Nous allons utiliser une application toute simple, une page web avec un Hello
World. Concourse-CI va se charger de builder notre application puis Flux se chargera
continuellement de la déployer sur notre cluster Kubernetes. Nous changerons le
code de cette application et observerons le résultat.

## Préparation

### Notre application

Je vais utiliser cette application :
<https://github.com/alterway/demo-concourse-flux>

L'application est composée d'un fichier index.php et d'une image PNG. Le
Dockerfile servant à builder l'application se trouve à la racine et j'ai crée
un dossier "deploy" dans lequel se trouvent [les déclarations de ressources
Kubernetes](https://github.com/alterway/demo-concourse-flux/blob/master/deploy/helloworld.yml). Le cluster Kubernetes sur lequel sera déployée l'application est en 1.15.

### Mise en place de Concourse

<center>
![concourse-logo](/images/concourse-logo.png)
</center>

<https://concourse-ci.org/install.html>

On ne rentre pas dans le détail ici, il n'y a rien de spécial à connaitre ou à
effectuer côté Concourse.

### Mise en place de Flux

<https://github.com/weaveworks/flux/blob/master/site/get-started.md>

Tout se déploie naturellement directement sur Kubernetes :

```bash
git clone https://github.com/weaveworks/flux
cd flux/
```

Un seul fichier a besoin d'être édité : `deploy/flux-deployment.yaml`

```bash
- --git-url=ssh://git@github.com/alterway/demo-concourse-flux
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

## Création du Pipeline

```yaml
resources:
  - name: git
    type: git
    source:
      uri: https://github.com/alterway/demo-concourse-flux
      branch: master
  - name: version
    type: semver
    source:
      driver: git
      uri: git@github.com:alterway/demo-concourse-flux
      branch: version
      file: version
      private_key: {{rguichard_pkey}}
  - name: image-helloworld
    type: docker-image
    source:
      repository: osones/demo-concourse-flux
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


## Configuration Flux

La majeure partie du travail a déjà été effectué en réalité. Il nous reste
seulement à ajouter quelques annotations à notre déployement pour préciser à
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
ts=2019-06-26T16:49:23.845635134Z caller=daemon.go:652 component=daemon event="**Automated release of osones/demo-concourse-flux:1.0.1**" logupstream=false
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

# Et GitOps dans tout ça ?

Et bien on y est. Si vous avez des changements à faire, ceux ci ne passeront
qu'au travers d'un commit ou d'une PR sur le dépot
<https://github.com/alterway/demo-concourse-flux>. Vous pouvez vous amusez à
changer la couleur du texte et à voir Concourse builder votre nouvelle image
puis Flux la déployer et synchroniser l'état de l'application sur le cluster
Kubernetes avec la déclaration du `deployment` dans Git.

Et si vous souhaitez changer la définition de votre Ingress, vous pouvez commit
ces changements et voir Flux (Concourse n'intervient pas ici) mettre à jour
votre Ingress sur votre cluster sans que vous ayez à vous connecter à votre
cluster et lancer un `kubectl apply`.



**Romain Guichard - [@herrguichard](https://twitter.com/herrguichard)**
