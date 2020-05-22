---
Title: "Kubernetes: semantic release avec Flux CD"
Date: 2020-02-21T11:00:00+02:00
Category: Kubernetes
Summary: Utiliser Semantic Versioning pour gérer proprement vos déploiements continus avec Flux CD
Author: Kevin Lefevre
image: images/thumbnails/flux-horizontal-color.png
imgSocialNetwork: images/og/flux-semver.png
lang: fr
---

## Semantic release avec Flux CD

### GitOps

2020 commence, c'est le moment de se lancer dans le GitOps et si vous souhaitez participer au bingo Cloud Natif, pourquoi pas continuer dans le FinOps et AIOps pour finir en NoOps.

Plus sérieusement nous avions déjà couvert le GitOps avec un premier article sur [Flux et Concourse](https://particule.io/blog/cicd-concourse-flux/) que je vous invite à parcourir pour se remettre en tête les définitions. Nous y montrons l'exemple d'une chaîne d'intégration continue, du build d'une image jusqu'à son passage en production avec Flux CD, Concourse CI et Kubernetes. Tout ceci avec un unique commit.

Si vraiment vous passez en coup de vent, globalement le GitOps consiste à mettre tout notre code déclaratif dans Git (dans notre cas, des manifests Kubernetes) et attendre que quelque chose fasse une action quelque part avec tout ce code.

Ici, le quelque chose est **Flux** et le quelque part **Kubernetes**.

### Flux CD

Flux est un projet incubé [dans la CNCF](https://particule.io/blog/weave-flux-cncf-incubation/) depuis peu, c'est un projet que nous apprécions beaucoup et dont nous poussons l'adoption chez nos clients.

Flux va permettre deux choses :

* Synchronisation du contenu d'un dépôt Git avec votre cluster Kubernetes
* Déploiement automatique de nouvelles images Docker

### Prérequis

* Un cluster Kubernetes
* `kubectl`
* `helm >= v3.0.0`

### Déploiement de Flux avec Helm v3

2020, exit tiller et Helm v2, nous allons rester edgy et déployer Flux avec Helm version 3.

Pour cela nous allons créer un fichier de `values.yaml`

```yaml
syncGarbageCollection:
  enabled: true
git:
  url: "ssh://git@github.com/particuleio/gitops-demo.git"
  pollInterval: "2m"
registry:
  automationInterval: "2m"
```

Nous allons ensuite déployer le chart :

```console
$ kubectl create namespace flux
helm repo add fluxcd https://charts.fluxcd.io
helm repo update
helm upgrade -i flux fluxcd/flux --namespace flux --values values.yaml
```

Si vous regardez les logs de Flux :

```console
$ kubectl -n flux logs -f flux-77c7d965d-w8sql

ts=2020-02-21T14:59:54.403665249Z caller=loop.go:107 component=sync-loop err="git repo not ready: git clone --mirror: fatal: Could not read from remote repository., full output:\n Cloning into bare repository '/tmp/flux-gitclone795667632'...\ngit@github.com: Permission denied (publickey).\r\nfatal: Could not read from remote repository.\n\nPlease make sure you have the correct access rights\nand the repository exists.\n"
```

Il faut donner à Flux les droits d'accès au dépot git qui va contenir nos manifests Kubernetes.

Pour cela, il faut récupérer la clé publique générée par Flux :

```console
$ kubectl -n flux logs deployment/flux | grep identity.pub | cut -d '"' -f2

ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC2OEG/277kY2Q+/p9NoYYfWvncDQUbgwwhHPKCWvjFiVwewcMQooSHw+egr4nTSWZPsMfwrwLTRD6BXTnofLa8MrhNKjXdp1YR+lrLlBYmL7EPFjxvAhFu1aA77odSMQzLJQNl5/2Ef+m+VnfNFKrB+m6VjELAA5VNvQ2qni3jcYbYrr9mjxQkZnDlkZNz9iIwbw/GSUaAH9gYtUNcClFZaZR0POp96C5L5Jc0tyO41Zzj77UlpLYDlUUK8iX9U507/HgHNsA9fvJDt+lGfa+0xgHCN3gzdxsgNFVAF1A/RRW0/d/QnQ8g7PE4oNiYwMyWUuAHZMtLZqI0xdUQ8SVPtNFtDeyOkrm3vpYlQE2S8cBof96oLR8wDyPzAU6QYdS2QPxWNumdi2fK0iQbcEs+qLIY5+pD0f+60OV5YVz8QsVejp/rtrGPb39o9tAuDdwGYeRs0Agn6DnyZzcafk16uxzJ4DANZ6N6YX0IbVESFIQf0qYXz7azyOq0ill+CMM= root@flux-77c7d965d-w8sql
```

Cette clé doit ensuite être ajoutée au repository git défini précédemment. Dans l'exemple de Github, plusieurs options :

* Une deploy key sur votre repository
* Une clé ssh dans votre utilisateur Github

![Flux Deploy Key](/images/flux-deploy-key.png#center)

Le principe reste le même pour les autres solutions Git en SaaS telle que Gitlab, Bitbucket etc.

Une fois la clé rajoutée, regardez les logs de Flux :

```console
ts=2020-02-21T15:09:48.522015918Z caller=loop.go:133 component=sync-loop event=refreshed url=ssh://git@github.com/particuleio/gitops-demo.git branch=master HEAD=ef677068fc473c3310bae58663ec3f02b5bb3652
```

Toute les minutes, Flux va appliquer les fichiers yaml présents dans le dépot Git.

Le repository utilisé pour l'exemple est disponible [ici](https://github.com/particuleio/gitops-demo)

### Gérer son déploiement automatisé avec Flux

[Semver](https://semver.org/) est une bonne pratique pour gérer les versions d'applications. Dans [notre article précédent](https://particule.io/blog/cicd-concourse-flux/) nous avons traité des cas simples pour déployer des applications en respectant un tag donné. Si vous êtes toujours aussi pressés qu'en début d'article, en resumé, Flux peut automatiser le déploiement de nouvelles images Docker lorsque celles ci sont poussées sur une registry Docker. Pour cela, de simples labels sur un Deployment suffisent :

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: test-flux
  name: test-flux
  namespace: default
  annotations:
    flux.weave.works/automated: "true"
    flux.weave.works/tag.test-flux: "semver:~1.0"
spec:
  replicas: 1
  revisionHistoryLimit: 1
  selector:
    matchLabels:
      app: test-flux
  template:
    metadata:
      labels:
        app: test-flux
    spec:
      containers:
      - image: particule/test-flux:v1.0.0
        imagePullPolicy: Always
        name: test-flux
```

Par exemple `semver:~1.0` qui va déployer toutes les images Docker avec un tag `>= 1.0, < 1.1` donc toutes les images en `1.0.X`. C'est globalement l'example donné dans la [documentation officielle](https://docs.fluxcd.io/en/1.18.0/references/automated-image-update.html).

Pour cet article j'ai créé un [repository Docker public](https://hub.docker.com/r/particule/test-flux/tags) avec des tags aléatoires disponibles pour des tests.

```console
docker images
REPOSITORY             TAG                 IMAGE ID            CREATED             SIZE
particule/test-flux   v1.0.0              2073e0bcb60e        2 weeks ago         127MB
particule/test-flux   v1.0.0-rc.1         2073e0bcb60e        2 weeks ago         127MB
particule/test-flux   v1.0.0-rc.2         2073e0bcb60e        2 weeks ago         127MB
particule/test-flux   v1.0.1              2073e0bcb60e        2 weeks ago         127MB
particule/test-flux   v1.0.1-rc.1         2073e0bcb60e        2 weeks ago         127MB
particule/test-flux   v1.0.1-rc.2         2073e0bcb60e        2 weeks ago         127MB
particule/test-flux   v1.0.2              2073e0bcb60e        2 weeks ago         127MB
particule/test-flux   v1.0.3-rc.5         2073e0bcb60e        2 weeks ago         127MB
particule/test-flux   v1.2.1              2073e0bcb60e        2 weeks ago         127MB
particule/test-flux   v2.1.6              2073e0bcb60e        2 weeks ago         127MB
particule/test-flux   v2.7.0              2073e0bcb60e        2 weeks ago         127MB
particule/test-flux   v3.5.0-rc.6         2073e0bcb60e        2 weeks ago         127MB
particule/test-flux   v3.5.0-rc.7         2073e0bcb60e        2 weeks ago         127MB
particule/test-flux   v3.5.4              2073e0bcb60e        2 weeks ago         127MB
particule/test-flux   v5.0.0              2073e0bcb60e        2 weeks ago         127MB
particule/test-flux   v5.1.0              2073e0bcb60e        2 weeks ago         127MB
particule/test-flux   v5.1.2              2073e0bcb60e        2 weeks ago         127MB
particule/test-flux   v5.1.6              2073e0bcb60e        2 weeks ago         127MB
```

Il n'y pas si longtemps on m'a demandé de déployer uniquement les images en `1.0.0-rc.X` jusqu'a `1.0.0` mais sans inclure la `1.0.1`. Si vous tester l'exemple donné dans la documentation avec le depot Gitops d'exemple, donc avec le couple :

```yaml
...
  annotations:
    flux.weave.works/automated: "true"
    flux.weave.works/tag.test-flux: "semver:~1.0.0"
...
image: particule/test-flux:v1.0.0-rc.1
```

Une fois le ficher `commit` et `push`, le pod est déployé en `v1.0.0-rc.1` puis lorsque Flux scan les nouvelles images sur le Docker Hub, la nouvelle image déployée est `1.0.2` qui ne répond pas au besoin.

Autre option :

```yaml
...
  annotations:
    flux.weave.works/automated: "true"
    flux.weave.works/tag.test-flux: "semver:~1.0.0-rc.x"
...
image: particule/test-flux:v1.0.0-rc.1
```

Nous nous retrouvons avec la version `1.0.3-rc.5` qui ne répond pas au besoin.

La révélation, et vraiment la raison pour laquelle j'écris ces quelques dizaines de lignes (merci la communauté / slack CNCF) est que les filtres `semver` ne se limitent pas au `~`, qui est en fait un [Tilde Range Comparisons](https://github.com/Masterminds/semver#tilde-range-comparisons-patch). Flux supporte tous les types de comparaisons décris [ici](https://github.com/Masterminds/semver) ainsi que les [*prereleases*](https://github.com/Masterminds/semver#working-with-prerelease-versions)

Dans notre cas précédent, il est donc possible de tester avec le couple suivant :

```yaml
...
  annotations:
    flux.weave.works/automated: "true"
    flux.weave.works/tag.test-flux: "semver: >= 1.0.0-rc.0, <1.0.1"
...
image: particule/test-flux:v1.0.0-rc.1
```

L'image déployée est `1.0.0` qui est la plus récente image respectant la contrainte de départ.

Tout cela pour cela ? Oui. N'hésitez pas à tester avec différents ranges, et si vous le saviez dejà, une [petite PR dans la documentation](https://github.com/fluxcd/flux/pull/2866) aurait été appréciée ;)

Si vous avez plus de temps maintenant n'hésitez pas à parcourir notre autre article sur [Flux et Concourse](https://particule.io/blog/cicd-concourse-flux/), d'autre articles sur [le blog](https://particule.io/blog/) ou bien [nous contacter](https://particule.io/#contact)

[**Kevin Lefevre**](https://www.linkedin.com/in/kevinlefevre/)

