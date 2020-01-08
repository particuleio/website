---
Title: Construire un pipeline de déploiement continu avec Kubernetes et Concourse-CI
Date: 2018-02-05
Category: CI/CD
Summary: Combiner Concourse-CI et Kubernetes pour construire un pipeline de déploiement pour vos applications
Author: Romain Guichard
image: images/thumbnails/kubernetes.png
lang: fr
---

<br />
# Introduction

Compiler/builder et déployer manuellement des applications conteneurisées est __généralement lent et source de nombreuses erreurs__.

Le déploiement continu permet d'automatiser la compilation de votre projet, la création de l'image Docker correspondante, les tests inhérents à votre application ainsi que le déploiement final sur votre orchestrateur préféré (si ce n'est pas encore Kubernetes, [Osones propose une formation](http://osones.com/formations/kubernetes.fr.html) pour combler ce trou dans votre raquette). Cet enchainement permet d'__assurer une reproductibilité quasiment parfaite__, accélère bien évidemment le temps entre la modification du code source et le déploiement en production. __En tant qu'Ops nous gagnons en sérénité__ et gagnons du temps !


Dans cet article, __nous utiliserons [Concourse-CI](https://concourse.ci/) comme outil de CI/CD et [Kubernetes](https://kubernetes.io/) comme orchestrateur de conteneurs__. Nous ne nous arrêtons pas sur le déploiement de ces deux outils, néanmoins, transparence oblige, je ne voudrais pas avoir de problème, Kubernetes est déployé via [kubeadm](https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/) en version 1.9.2 et Concourse-CI via des conteneurs dont [les images sont fournies](https://hub.docker.com/r/concourse/concourse/) en version 3.8.0.


Le workflow sera le suivant :

* Commit et pusher votre code (sur GitHub dans notre exemple)
* Concourse déclenchera le build de votre application et de l'image Docker associée
* Concourse déploiera votre application sur Kubernetes
* Via différents objets de l'API, nous rendrons cette application disponible à vos utilisateurs

En fonction de la nature de vos tests (couverture de code, unitaires, non régression etc) ils seront à placer intelligemment entre ces étapes.

Pas de questions ?

Let's go !

# Préparation de l'environnement

On va avoir besoin de __quelques outils__ avant de démarrer :

* Un répo public GitHub (pour notre code)
* Un compte sur DockerHub (pour nos images Docker)
* De credentials pour se connecter à Kubernetes

On va créer notre projet sur GitHub (le répo doit être créé au préalable) :
```
$ mkdir demo-cicd && cd demo-cicd
$ git init
$ git remote add origin https://github.com/osones/demo-cicd
$ touch README.md
$ git add README.md && git commit README.md -m "init"
$ git push -u origin
```

L'application que nous utiliserons comme démonstrateur est celle ci :
[https://github.com/osones/demo-cicd](https://github.com/osones/demo-cicd)

Elle est volontairement extrêmement simple et ne fait qu'afficher notre logo ainsi qu'un hello world et est à 99% dérivée de l'application [hello-world de dockercloud](https://hub.docker.com/r/dockercloud/hello-world/).

On peut attaquer la configuration de Concourse-CI !

# Concourse-CI

![Concourse CI](/images/concourse-logo.png#center)

Comme prévenu, je ne reviendrais pas en détails sur Concourse et son fonctionnement. Pour faire court, __Concourse est un outil de CI/CD écrit en Go, nativement prévu pour tourner sur des infrastructures cloud et pour scaler__. Il fonctionne sur des "ressources" permettant de récupérer des images Docker, de pusher sur S3, créer des ressources Kubernetes etc. Tout se décrit dans des fichiers yml et tout est donc versionnable, Concourse ne stocke quasiment rien. Voilà pour l'intro ;)


Notre pipeline va ressembler à quelque chose comme ça :

Tout d'abord nos ressources :
```
resource_types:
- name: kubernetes
  type: docker-image
  source:
    repository: zlabjp/kubernetes-resource
    tag: "1.9"

resources:
  - name: git-demo
    type: git
    source:
      uri: https://github.com/osones/demo-cicd
      branch: master
  - name: docker-demo
    type: docker-image
    source:
      repository: osones/demo-cicd
      username: rguichard
      password: {{dh-rguichard-passwd}}
  - name: k8s
    type: kubernetes
    source:
      kubeconfig: {{k8s_server}}
```
On défini 3 ressources :

* notre répo GitHub (attention, la ressource "git" utilise l'API GitHub et vous pouvez vous heurter au rate limit de cette API. Pour s'en affranchir (partiellement), vous pouvez fournir votre clé privée à la ressource, de cette façon, vous serez authentifiés et l'API vous donnera plus de latitude)
* notre repository sur DockerHub (pensez à fournir votre password dans le yml de credentials ;) )
* notre ressource Kubernetes. Cette ressource n'est pas officielle et on peut voir que je l'importe en haut du fichier.

Maintenant nos jobs :

```
jobs:
  - name: "Docker-Build"
    public: false
    plan:
      - get: git-demo
        trigger: true
      - put: docker-demo
        params:
          build: git-demo
  - name: "Deploy Application"
    public: false
    plan:
      - get: docker-demo
        trigger: true
        passed:
          - "Docker-Build"
      - put: k8s
        params:
          kubectl: delete pods -l app=demo-cicd
          wait_until_ready: 300
```

Seulement deux jobs ! Le premier build notre image à partir des sources. __C'est là qu'on voit la puissance de Concourse : le job en question fait seulement 6 lignes__. Le second job se contente de déclencher un rolling update sur Kubernetes si une nouvelle image Docker est détectée.

Pour updater notre application, on décide simplement de kill notre pod (merci les labels), notre deployment se chargera d'en lancer un nouveau avec la nouvelle image. Cela implique effectivement que l'application ai déjà été déployée une première fois. On aurai pu redéployer "normalement", cela ne change pas grand chose ;)

Et on déploie notre pipeline !
```
$ fly -t osones set-pipeline -p demo-cicd -c demo-cicd.yml --load-vars-from secrets/demo-cicd.yml
$ fly -t osones unpause-pipeline -p demo-cicd
```
Dans notre `secrets/demo-cicd.yml` vous devrez retrouvez les variables utilisées dans votre pipeline.

![Pipeline](/images/pipeline-concourse-k8s-cd.png#center)

Passons maintenant Kubernetes :

# Kubernetes

![Kubernetes](/images/docker/kubernetes.png#center)

On va utiliser 3 objets pour notre application, un deployment, un service et un ingress. Notre ingress controller sera assuré par Traefik [dont nous avons déjà pas mal parlé sur le blog](https://blog.osones.com/kubernetes-ingress-controller-avec-traefik-et-lets-encrypt.html).

```
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  namespace: default
  name: demo-cicd
  labels:
    app: demo-cicd
spec:
  replicas: 3
  revisionHistoryLimit: 2
  template:
    metadata:
      namespace: default
      labels:
        app: demo-cicd
    spec:
      containers:
        - name: demo-cicd
          image: osones/demo-cicd:latest
          imagePullPolicy: Always
---
apiVersion: v1
kind: Service
metadata:
  namespace: default
  name: demo-cicd-svc
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
  selector:
    app: demo-cicd
  type: ClusterIP
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  namespace: default
  name: demo-cicd
  annotations:
    kubernetes.io/ingress.class: traefik
spec:
  rules:
    - host: demo-cicd.osones.com
      http:
        paths:
          - backend:
              serviceName: demo-cicd-svc
              servicePort: 80
```
Le paramètre `imagePullPolicy: Always` est important car il permet de dire à Kubernetes de puller notre image à chaque déploiement. Ce qui permettra son update lors du `kubectl delete pod` déclenché par Concourse.

Comme on doute de nous, donc on va quand même aller vérifier sur notre cluster que les pods sont bien présents :
```
$ kubectl get pods -l app=demo-cicd
ds -l app=demo-cicd
NAME                         READY     STATUS    RESTARTS   AGE
demo-cicd-58c9f4c994-9dbm7   1/1       Running   0          1m
demo-cicd-58c9f4c994-hxmnf   1/1       Running   0          1m
demo-cicd-58c9f4c994-q8tnh   1/1       Running   0          1m
```
Le doute écarté, on peut constater que notre page est bien accessible :

![helloworld-red](/images/helloworld-osones-rouge.png#center)

On peut avec plaisir constater que le load balancing entre nos 3 conteneurs est parfaitement fonctionnel si vous rafraichissez plusieurs fois la page (attention au cache ;) ).

Maintenant on va décider de changer la couleur et de passer notre titre en vert :

```
$ sed -i s/red/green/ index.php
$ git commit -am "from red to green" && git push
```

Et on attend que la CI fasse tourner tout ça ! 3 min plus tard :

![helloworld-green](/images/helloworld-osones-vert.png#center)

Tout ça est vraiment simple, nous n'avons apporté aucune complexité au pipeline. Dans les axes d'améliorations possibles on peut citer :

* Utiliser la ressource semver pour gérer les numéros de version
* Lancer des tests pour valider que la nouvelle image est fonctionnelle
* Utiliser d'autres méthodes de [rolling update sur Kubernetes](https://kubernetes.io/docs/tutorials/kubernetes-basics/update-intro/), la notre est un peu violente...
* Publier une release github (une ressource existe pour ça aussi ! ) lorsque le déploiement est terminé et le nouvelle version validée
* ...


# Rejoignez vous aussi la conversation !

** - Questions, remarques, suggestions... Contactez-nous directement sur Twitter sur [@osones](https://twitter.com/osones) !**
** - Pour discuter avec nous de vos projets, nous restons disponibles directement via contact@osones.com !**


**[Romain Guichard](https://fr.linkedin.com/in/romainguichard/en)**
