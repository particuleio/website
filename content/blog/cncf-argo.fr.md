---
Title: La CNCF adopte Argo
Date: 2020-04-15
Category: Kubernetes
Summary: La CNCF adopte Argo dans les projets en [incubation](https://www.cncf.io/projects/)
Author: Kevin Lefevre
image: images/argo/argo-logo.png
lang: fr
---

### Continuité du mouvement Gitops

Qu'est ce que le Gitops ? nous en avions déjà un peu parlé [par-ci](https://particule.io/blog/cicd-concourse-flux/), [par-là](https://particule.io/blog/flux-semver/), notamment avec [FluxCD](https://particule.io/blog/weave-flux-cncf-incubation/) pour la partie technique.

Le Gitops est un ensemble d'outils et de best practices dans la continuité du mouvement DevOps pour gérer le déploiement de vos applications et/ou infrastructures avec Git en tant que point de référence, pour cela nous avons besoin d'au moins 3 choses essentielles :

* Un dépôt de code
* Un endroit oú déployer
* Une *glue* qui va nous permettre de réaliser des actions en fonction du premier sur le précèdent

Cette *glue* se découpe souvent en deux catégories :

* Build : Continuous Integration
* Deployment : Continuous Delivery

Et dans ces catégories ils existent de nombreux outils tels que [Jenkins](https://jenkins.io/), [Gitlab](https://docs.gitlab.com/ee/ci/), ou encore [Travis](https://travis-ci.com/). Il existe également des outils dédiés à la partie CD, tels que [Spinnaker](https://www.spinnaker.io/), Weave [Flagger](https://github.com/weaveworks/flagger) et [Flux](https://www.weave.works/oss/flux/).

### Quid d'[Argo](https://argoproj.github.io/) ?

Argo est un projet qui a pour but d'unifier les différentes étapes de "delivery" sous une seule plateforme, et cela sous la [bannière de la CNCF](https://www.cncf.io/blog/2020/04/07/toc-welcomes-argo-into-the-cncf-incubator/).

Comme beaucoup de projets de la CNCF, Argo s'articule autour de Kubernetes, et l'étend afin d'ajouter des fonctionnalités.

Argo se décompose en sous projets qui répondent chacun à une problématique précise.

#### [Argo Workflow](https://argoproj.github.io/projects/argo)

Création de pipeline de CI native à Kubernetes : Pods, Jobs, etc ainsi que orchestration et gestion des artifacts qui peut se comparer à un outil de CI classique.

#### [Argo CD](https://argoproj.github.io/projects/argo-cd)

Comme son nom l'indique, permet la partie Continuous Delivery, il permet entre autres de déployer des versions spécifiques d'applications et de réconcilier l'état demandé avec l'état actuel du cluster. Argo CD supporte [Helm](https://helm.sh/), [Ksonnet](https://ksonnet.io/), [Jsonnet](https://jsonnet.org/) et [Kustomize](https://kustomize.io/) en plus des manifests Kubernetes classiques.

![argo-cd](/images/argo/argocd_architecture.png#center)

#### [Argo Rollout](https://argoproj.github.io/argo-rollouts/)

Augmente les stratégies de déploiement fournies de base dans Kubernetes et ajoute la fonctionnalité de *Canary Deployment* ainsi que *Blue/Green Deployment*.

#### [Argo Event](https://argoproj.github.io/projects/argo-events)

Permet d'exécuter des [actions](https://argoproj.github.io/argo-events/concepts/trigger/) en fonctions [d'événement extérieurs](https://argoproj.github.io/argo-events/concepts/event_source/). Par exemple de lancer un pipeline Argo Workflow après une notification sur [AWS SNS](https://aws.amazon.com/fr/sns/).

![argo-event](/images/argo/argo-events-top-level.png#center)

### Futur des projets

Comme souvent ces projets ne sont pas les seuls sur le marché, c'est notamment le cas de Argo CD qui fourni des fonctionnalité similaires à [Flux CD](https://fluxcd.io/).

Sur la partie Continuous Delivery, Argo CD et Flux ont maintenant un [projet commun](https://www.weave.works/blog/argo-flux-join-forces): Argo Flux afin de mutualiser les fonctionnalités des deux applications.

Cela permettra notamment d'apporter à Argo CD la fonctionnalité que nous apprécions particulièrement dans Flux CD qui est la surveillance de registries Docker pour déployer de nouvelles image en fonction de [glob et/ou semver](https://particule.io/blog/flux-semver/). Ce projet sera un projet conjoint au sein de la CNCF.

Dans la même lignée, un rapprochement entre [Weave Flagger et Argo Rollout est envisageable](https://www.weave.works/blog/argo-flux-join-forces) puisque les deux fournissent également des fonctionnalités similaires.

**Kevin Lefevre**
