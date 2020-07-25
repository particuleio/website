---
Title: Utilisation de Kustomize avec Flux CD
Date: 2020-06-10
Category: Kubernetes
Summary: Profiter de Kustomize intégré à Flux CD pour appliquer vos YAML Kubernetes à la volée sur de multiples environnements en respectant les principes GitOps.
Author: Kevin Lefevre
image: images/thumbnails/flux-horizontal-color.png
imgSocialNetwork: images/og/kustomize-flux.png
lang: fr
---

Aujourd'hui, nous allons parler de deux sujets, un dont nous parlons chaque
semaine : [GitOps](https://www.weave.works/technologies/gitops/), et un dont
nous n'avons jamais parlé :
[Kustomize](https://github.com/kubernetes-sigs/kustomize).

Nous sommes depuis un petit moment de fervents utilisateurs de
[Helm](https://helm.sh/). Helm est une solution de templating pour manifestes
Kubernetes se basant sur [Go template](https://golang.org/pkg/text/template/).
C'est un petit peu la référence en terme de "packaging" d'application Kubernetes.
Vous pouvez
trouvez des Helm Charts officiels et communautaires pour la plupart de vos
middlewares, par exemple
[rabbitmq](https://github.com/helm/charts/tree/master/stable/rabbitmq) ou encore
[Kong](https://github.com/Kong/charts). Ces Charts sont notamment centralisés
sur le [Helm Hub](https://hub.helm.sh/).

Certains Charts sont très complets et cela vous évite de réinventer la roue et
de profiter de l'avancement de la communauté lorsque que vous souhaitez utiliser
des solutions communément déployées.

Sauf qu'arrive ensuite le moment où vous devez packager vos propres application.
Dans ce cas, pas de Helm Chart officiel.

La première solution serait de rester natif à Kubernetes et d'écrire ses propres
fichiers YAML et de les dupliquer par environnement. C'est un peu la première
étape de réflexion. Dans un cas de multi environnements, par exemple avec le
classique `staging`, `preprod`, `prod`, vous allez vite vous retrouvez à
dupliquer vos fichiers YAML, et comme d'habitude en ce qui concerne la
duplication de code : fastidieux et source d'erreurs.

C'est là qu'interviennent les outils de templating, il en existe légion avec
chacun leur caractéristiques. Pour ne citer qu'eux :

* [Helm](https://helm.sh/)
* [Kustomize](https://github.com/kubernetes-sigs/kustomize)
* [kpt](https://github.com/GoogleContainerTools/kpt)
* [k14's ytt](https://get-ytt.io/)

Nous n'allons pas ici faire un comparatif exhaustif des différentes solutions,
chacune est un peu philosophiquement différente. Nous allons surtout nous
concentrer sur [Kustomize](https://github.com/kubernetes-sigs/kustomize).

Helm est clairement l'outil le plus connu et le plus utilisé. Mais lorsque l'on
débute avec les manifestes Kubernetes, la marche peut être assez haute :
il faut en plus d'être à l'aise avec l'API Kubernetes, apprendre un nouveau
système de templating (Go Template) ainsi que les [best practices liées a
Helm](https://helm.sh/docs/chart_best_practices/).

### Démarrer avec Kustomize

C'est ici qu'intervient
[Kustomize](https://github.com/kubernetes-sigs/kustomize), qui était à la base
un outil standalone mais qui est maintenant [intégré à
`kubectl`](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)
depuis Kubernetes v1.14.0.

L'avantage de Kustomize, en plus d'être natif à Kubernetes, est qu'il ne
nécessite pas de notions de templating avancées. Kustomize se base sur la notion
de patch, si vous avez déjà utilisé la commande `kubectl patch` afin de mettre à
jour une ressource, le fonctionnement est un peu équivalent, nous allons voir
cela par la suite.

Nous allons partir de ce [dépôt
Git](https://github.com/particuleio/gitops-demo/kustomize) et d'un cluster
Kubernetes.

Nous allons créer deux `namespaces`:

```console
kubectl create ns preprod
kubectl create ns prod
```

La structure du dossier `kustomize` est la suivante :

```console
.
├── base
│   ├── helloworld-de.yaml
│   ├── helloworld-hpa.yaml
│   ├── helloworld-svc.yaml
│   └── kustomization.yaml
├── preprod
│   └── kustomization.yaml
└── prod
    ├── kustomization.yaml
    └── replicas-patch.yaml
```

Regardons un peu plus en détail. Notre dossier `base` contient nos manifestes
YAML de référence. Ce sont des manifestes Kubernetes classiques. Nous avons un
`Deployment`, un `Service` et un `HorizontalPodAutoscaler`.

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: helloworld
  labels:
    app: helloworld
spec:
  revisionHistoryLimit: 2
  selector:
    matchLabels:
      app: helloworld
  template:
    metadata:
      labels:
        app: helloworld
    spec:
      containers:
      - name: helloworld
        image: particule/helloworld
        imagePullPolicy: Always
        ports:
        - name: web
          containerPort: 80
apiVersion: autoscaling/v2beta1
kind: HorizontalPodAutoscaler
metadata:
  name: helloworld
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: helloworld
  minReplicas: 1
  maxReplicas: 2
  metrics:
  - type: Resource
    resource:
      name: cpu
      targetAverageUtilization: 60
---
apiVersion: v1
kind: Service
metadata:
  name: helloworld
spec:
  ports:
  - port: 80
  selector:
    app: helloworld
  type: NodePort
```

On remarque que nos ressources ne spécifient pas de `namespace`. Ces manifestes
ne seront techniquement jamais déployés mais serviront de base pour nos futurs
déploiements dans leurs `namespaces` respectifs. En plus, notre dossier base
contient un fichier `kustomization.yaml` listant les YAML gérés par Kustomize :

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- helloworld-de.yaml
- helloworld-svc.yaml
- helloworld-hpa.yaml
```

Notre prochain objectif est de générer automatiquement les YAML pour nos deux
environnements de `preprod` et `prod`. Commençons par la `preprod`.

Dans le dossier `preprod` nous avons uniquement un fichier `kustomization.yaml` :

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
bases:
- ../base/
namespace: preprod
namePrefix: preprod-
```

Alors que signifie ce fichier ? Dans un premier temps nous allons charger tous
les manifestes présents dans le dossier `base`. Ensuite nous allons appliquer un
`namespace` à toutes ces ressources. Et enfin nous allons préfixer toutes les
ressources par le nom du `namespace`, ici `preprod-`.

Observons le résultat. Comme nous le disions en début d'article, Kustomize est
intégré à `kubectl`, pas besoin d'outils supplémentaires. Pour générer nos YAML
de `preprod` :

```yaml
$ kubectl kustomize preprod

apiVersion: v1
kind: Service
metadata:
  name: preprod-helloworld
  namespace: preprod
spec:
  ports:
  - port: 80
  selector:
    app: helloworld
  type: NodePort
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: helloworld
  name: preprod-helloworld
  namespace: preprod
spec:
  revisionHistoryLimit: 2
  selector:
    matchLabels:
      app: helloworld
  template:
    metadata:
      labels:
        app: helloworld
    spec:
      containers:
      - image: particule/helloworld
        imagePullPolicy: Always
        name: helloworld
        ports:
        - containerPort: 80
          name: web
---
apiVersion: autoscaling/v2beta1
kind: HorizontalPodAutoscaler
metadata:
  name: preprod-helloworld
  namespace: preprod
spec:
  maxReplicas: 2
  metrics:
  - resource:
      name: cpu
      targetAverageUtilization: 60
    type: Resource
  minReplicas: 1
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: preprod-helloworld
```

On remarque bien les subtiles différences entre `base` et `preprod`.

Attaquons nous maintenant à la `prod`. Pour cela, même principe, un fichier
`kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
bases:
- ../base/
namespace: prod
namePrefix: prod-
patchesStrategicMerge:
- replicas-patch.yaml
```

Nous rajoutons un préfix ainsi que le `namespace`. Mais, pour corser un peu, nous
allons en plus patcher une des ressource. L'`Horizontal Pod Autoscaler` a par
défaut un nombre de replicas minimum fixé à `1` dans `base`. En `prod` nous
souhaitons en avoir un minimum de `2` et un maximum de `4`.

Le fichier `replicas-patch.yaml`:

```yaml
---
apiVersion: autoscaling/v2beta1
kind: HorizontalPodAutoscaler
metadata:
  name: helloworld
spec:
  minReplicas: 2
  maxReplicas: 4
```

Ici, pas le peine de définir toutes les spécifications de la ressource,
Kustomize va réaliser un patch de la ressource de `base` en remplaçant les
valeurs souhaitées.

Générons maintenant les manifestes de `prod` de la même façon que `preprod`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: prod-helloworld
  namespace: prod
spec:
  ports:
  - port: 80
  selector:
    app: helloworld
  type: NodePort
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: helloworld
  name: prod-helloworld
  namespace: prod
spec:
  revisionHistoryLimit: 2
  selector:
    matchLabels:
      app: helloworld
  template:
    metadata:
      labels:
        app: helloworld
    spec:
      containers:
      - image: particule/helloworld
        imagePullPolicy: Always
        name: helloworld
        ports:
        - containerPort: 80
          name: web
---
apiVersion: autoscaling/v2beta1
kind: HorizontalPodAutoscaler
metadata:
  name: prod-helloworld
  namespace: prod
spec:
  maxReplicas: 4
  metrics:
  - resource:
      name: cpu
      targetAverageUtilization: 60
    type: Resource
  minReplicas: 2
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: prod-helloworld
```

Remarquez les `maxReplicas` et `minReplicas` respectivement à `4` et `2` au
lieu de `2` et `1`.

Nous pouvons maintenant appliquer nos deux environnements :

```console
kubectl apply -k prod/
service/prod-helloworld created
deployment.apps/prod-helloworld created
horizontalpodautoscaler.autoscaling/prod-helloworld created

kubectl apply -k preprod/
service/preprod-helloworld created
deployment.apps/preprod-helloworld created
horizontalpodautoscaler.autoscaling/preprod-helloworld created
```

Vérifions nos ressources sur le cluster :

```console
kubectl -n preprod get hpa,deployments,services

NAME                                                     REFERENCE                       TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/preprod-helloworld   Deployment/preprod-helloworld   <unknown>/60%   1         2         1          38m

NAME                                 READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/preprod-helloworld   1/1     1            1           38m

NAME                         TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
service/preprod-helloworld   NodePort   10.103.2.95   <none>        80:30339/TCP   38m
```

```console
kubectl -n prod get hpa,deployments,services

NAME                                                  REFERENCE                    TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/prod-helloworld   Deployment/prod-helloworld   <unknown>/60%   2         4         2          36m

NAME                              READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prod-helloworld   2/2     2            2           36m

NAME                      TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
service/prod-helloworld   NodePort   10.107.91.161   <none>        80:31145/TCP   36m
```

Kustomize permet simplement de surcharger des manifestes YAML sans aucune
connaissance préalable niveau templating. Pour aller plus loin, [la référence
des possibilités est disponible
ici](https://kubectl.docs.kubernetes.io/pages/reference/kustomize.html)

### Déployer des templates Kustomize avec Flux CD

Maintenant que nous arrivons à générer nos manifestes pour nos deux
environnements, comment pouvons nous intégrer ce processus dans une logique
GitOps ?

Nous avons déjà beaucoup parlé de [Flux CD](https://fluxcd.io/)
[ici](https://particule.io/blog/cicd-concourse-flux/) et
[la](https://particule.io/blog/weave-flux-cncf-incubation/) et nous allons
encore en parler aujourd'hui puisque Flux permet la génération de manifestes
Kubernetes avec Kustomize. En theorie Flux [permet la génération de manifestes
via n'importe quelle commande de
templating](https://docs.fluxcd.io/en/1.19.0/references/fluxyaml-config-files/#generator-configuration)
mais nous allons ici nous concentrer sur la partie Kustomize.

Pour cela nous allons repartir de nos travaux précédents en créant un nouveau
dossier
[`kustomize-flux`](https://github.com/particuleio/gitops-demo/tree/master/kustomize-flux)
basé sur notre dossier `kustomize`.

La structure est la suivante :

```console
.
├── .flux.yaml
├── base
│   ├── helloworld-de.yaml
│   ├── helloworld-hpa.yaml
│   ├── helloworld-svc.yaml
│   └── kustomization.yaml
├── preprod
│   ├── flux-patch.yaml
│   └── kustomization.yaml
├── prod
│   ├── flux-patch.yaml
│   ├── kustomization.yaml
│   └── replicas-patch.yaml
├── values-flux-preprod.yaml
└── values-flux-prod.yaml
```

Voyons ensemble les fichiers supplémentaires.

#### Déploiement de Flux

Dans un premier temps nous avons deux fichiers de `values` Helm qui vont nous
servir à déployer deux instances de Flux sur notre cluster :

* `flux-preprod`

```yaml
git:
  pollInterval: 1m
  url: ssh://git@github.com/particuleio/gitops-demo.git
  branch: master
  path: kustomize-flux/preprod
syncGarbageCollection:
  enabled: true
manifestGeneration: true
additionalArgs:
-  --git-sync-tag=flux-sync-preprod
```

Cette instance de flux pointe sur le dossier `preprod`

* `flux-prod`

```yaml
git:
  pollInterval: 1m
  url: ssh://git@github.com/particuleio/gitops-demo.git
  branch: master
  path: kustomize-flux/prod
syncGarbageCollection:
  enabled: true
manifestGeneration: true
additionalArgs:
-  --git-sync-tag=flux-sync-prod
```

Cette instance de flux pointe sur le dossier `prod`

Nous pouvons ensuite déployer Flux via les commandes suivantes :

```console
helm upgrade -i flux-prod fluxcd/flux --namespace prod --values values-flux-prod.yaml

helm upgrade -i flux-preprod fluxcd/flux --namespace preprod --values values-flux-preprod.yaml
```

Vérifions que Flux est bien déployé :

```console
kubectl -n prod get pods
NAME                                   READY   STATUS    RESTARTS   AGE
flux-prod-588b66bb64-fsw5q             1/1     Running   0          31m
flux-prod-memcached-546c87f4d4-8rwtw   1/1     Running   0          34m
```

```console
kubectl -n preprod get pods
NAME                                      READY   STATUS    RESTARTS   AGE
flux-preprod-6bdc5dfb6-thqx9              1/1     Running   0          32m
flux-preprod-memcached-59f5454c6f-ldl25   1/1     Running   0          34m
```

#### Le fichier `.flux.yaml`

Un autre fichier additionnel est le fichier `.flux.yaml`, c'est lui qui va
indiquer à Flux comment générer les manifestes :

```yaml
version: 1
patchUpdated:
  generators:
    - command: kubectl kustomize .
  patchFile: flux-patch.yaml
```

Ici nous utilisons la même commande que celle utilisée pour générer les
manifestes manuellement.

En plus de cela, nous indiquons à Flux où se trouvent les patchs spécifiques à
Flux qui seront utilisés (par exemple dans le cas d'une release
automatisée, ou encore pour activer des paramètres spécifiques à Flux que nous
allons voir par la suite).


#### Les fichiers `flux-patch.yaml`

Si vous avez déjà parcouru nos [différents
articles](https://particule.io/blog/flux-semver/) [sur
Flux](https://particule.io/blog/cicd-concourse-flux/), vous savez qu'il
permet, en plus d'appliquer les fichiers YAML sur un cluster, de gérer le
déploiement automatisé des nouvelles images Docker en fonction de différentes règles
et notamment le [`semver`](https://semver.org/).

Cette fonctionnalité est gérée via des annotations sur les `deployments`, ces
annotations peuvent être différentes suivant les environnements, par exemple
dans notre cas nous allons interdire le déploiement automatisé en `prod` mais
nous allons l'activer en `preprod`.

Par exemple en `prod`, le fichier `flux-patch.yaml` :

* `prod/flux.yaml`

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    flux.weave.works/locked: "true"
    flux.weave.works/locked_msg: Lock deployment in production
    flux.weave.works/locked_user: Particule
  name: prod-helloworld
  namespace: prod
```

En `preprod` nous allons déployer toutes les versions `~1.X.X` :

* `preprod/flux-patch.yaml`

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    flux.weave.works/automated: "true"
    flux.weave.works/tag.helloworld: semver:~1
  name: preprod-helloworld
  namespace: preprod
```

Une fois que tout est prêt dans notre dépôt, nous pouvons activer Flux sur le
dépôt git, pour cela il nous faut récupérer la clé publique de chaque instance
de Flux et l'ajouter sur Github dans Settings -> Deploy Keys.

```console
kubectl -n preprod logs flux-pod | head

ts=2020-06-10T14:35:43.197547567Z caller=main.go:493 component=cluster identity.pub="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDNYjo5gddG6fXJg75L3gf2mXNBV+DKd9LPz9ZqK2phhwD0fI7J2LajxKnTQGtxj72VBqU+lweEP8YV15auswyjraIYLgnLEE5POb6H8Cjz0vfVX61j3fcLnH77n48GQDKWo0rYQ9hxSmSthi/E1FGy41thxOYRm/IIErN8whKC0+YWDeKlwLNZatSSs/3XA4Q3eCpdPWwAot8sEWDOexUeno/GyaDhBiHm7gxjKkMPsnW8lj9ovtCzjt2H+vLV57neIcx4hx/bhWr3z+wVxkbnDv8zIfXaziXfy5Ueuz0e9sQ3pE1lbrTkeumQN0ekHNAdRjpIa89RRok6KTfBFN7w8iXoLvuSR1NZe9/aunZwqG0ZDGXQjmE8/AHy00QhXmDQT+1VJX00uq/0Jx87v6yiHV+I3LyA1Rn946S4qpxsvFAqDVyKrxFy6WwDSDhd4GHAlI/gFE6dPn8FXqQtL9NVWUxTqFs6svHTLNq6orQ92oKELcsTPHvUyvflj+5JW6k= root@flux-preprod-865d6d9666-6w4x7"
```

Une fois les clés rajoutées, Flux commencera à déployer les ressources via
Kustomize.

```console
kubectl -n preprod logs -f flux-pod

ts=2020-06-10T14:11:29.602531682Z caller=sync.go:539 method=Sync cmd=apply args= count=3
ts=2020-06-10T14:11:29.98907821Z caller=sync.go:605 method=Sync cmd="kubectl apply -f -" took=386.489628ms err=null output="service/preprod-helloworld unchanged\ndeployment.apps/preprod-helloworld unchanged\nhorizontalpodautoscaler.autoscaling/preprod-helloworld unchanged"
```

```console
kubectl -n preprod logs -f flux-pod

ts=2020-06-10T14:13:58.283012811Z caller=sync.go:539 method=Sync cmd=apply args= count=3
ts=2020-06-10T14:13:58.684738069Z caller=sync.go:605 method=Sync cmd="kubectl apply -f -" took=401.666475ms err=null output="service/prod-helloworld unchanged\ndeployment.apps/prod-helloworld unchanged\nhorizontalpodautoscaler.autoscaling/prod-helloworld unchanged"
```

Nos ressources sont bien appliquées sur le cluster via Flux.

#### Test déploiement automatisé

Nous allons maintenant pousser sur le Docker Hub une nouvelle version `1.1` de
notre image Docker `helloworld` et voir si Flux met à jour notre déploiement
automatiquement ainsi que l'impact sur notre dépôt git.

```console
docker push particule/helloworld:1.1
```

Environ 5 minutes après (le polling interval par defaut de Flux). Flux devrait
commit sur git la mise à jour de l'image :

![](/images/flux/flux-update.png#center)

#### Détail sur le workflow

Que se passe t-il réellement sur le cluster ? Le workflow de déploiement de Flux
est le suivant dans le cadre du déploiement initial :

* Flux génère les YAML via Kustomize
* Flux applique les `flux-patch.yaml`
* Flux applique les manifestes sur le cluster

Dans le cas d'une mise à jour d'images :

* Flux scan les registry Docker
* Flux détecte la nouvelle image
* Flux met à jour sur le dépôt git le fichier `flux-patch.yaml` correspondant
* Répétition du workflow précèdent

#### Aller encore plus loin

Cet article a été inspiré par la [communauté
flux](https://github.com/fluxcd/flux-kustomize-example) qui propose des dépôts
git d'exemple afin de [déployer facilement des manifestes avec
Kustomize](https://github.com/fluxcd/multi-tenancy-team1) dans le cas de
[cluster multi-tenants](https://github.com/fluxcd/multi-tenancy).

La documentation officielle de cette fonctionnalité est également disponible
[ici](https://docs.fluxcd.io/en/latest/references/fluxyaml-config-files/)

### Conclusion

Nous vous avions déjà présenté Flux à maintes reprises. C'est un outils bourré
de fonctionnalités, du déploiement automatisé d'images au déploiement de Helm
Chart via [Helm Operator](https://github.com/fluxcd/helm-operator) en passant
par la génération de manifestes via Kustomize que nous l'avons couvert aujourd'hui.

Flux permet de centraliser vos manifestes Kubernetes et d'utiliser un workflow
GitOps tout en gardant la souplesse du choix de technologie, que ce soit via des
manifestes Kubernetes statiques, des Helm charts ou du Kustomize.

Nous verrons dans un prochain article comment gérer ce dépot Git hétérogène
composé de multiples technologies ainsi que l'intégration avec [Github
Action](https://github.com/features/actions) via
[`kubernetes-toolset`](https://github.com/marketplace/actions/kubernetes-toolset)

[**Kevin Lefevre**](https://www.linkedin.com/in/kevinlefevre/)
