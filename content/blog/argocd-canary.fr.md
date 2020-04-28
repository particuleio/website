---
Title: Canary deployment avec Argo
Date: 2020-04-27
Category: Kubernetes
Summary: Introduction à ArgoCD et Argo-Rollout, canary deployment, rollback, le tout *as code* !
Author: Romain Guichard
image: images/argo/argo-logo.png
lang: fr
---

Et oui on va encore parler de GitOps... [Dans notre dernier
article](https://particule.io/blog/cncf-argo/), nous avons
brièvement présenté Argo et [sa récente adoption par la
CNCF](https://www.cncf.io/projects/). Pour rappel, Argo est une suite
d'outils de Continuous Delivery :

- ArgoCD
- Argo Workflow
- Argo Rollout
- Argo Event

Je vous invite à reparcourir notre article si vous souhaitez vous rafraichir la
mémoire :

<https://particule.io/blog/cncf-argo/>

Les présentations étant effetuées, on va mettre en application ArgoCD et Argo
Rollout pour montrer comment nous pouvons, à partir d'un simple commit git,
déployer une mise à jour applicative de façon graduelle, controlée et assortie
d'un mécanisme de rollback automatique. Tout un programme.

# Notre application et ses releases

Je vais utiliser simple une application qui fournie une API renvoyant un code
json comme ceci :

```
{
  "color": "red",
  "status": "ok"
}
```

Oui c'est vraiment très simple. Nous allons nous servir de `color`  pour
pouvoir observer les montées de version de notre application et de `status` comme
une métrique de sa santé.

On va créer trois releases de notre application pour effectuer nos tests
d'update :

- `1.0` en mettant `color` à `red`
- `2.0` en mettant `color` à `blue`
- `3.0` en mettant `color` à `black` et `status` à `nok`


```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: colorapi
  labels:
    app: colorapi
spec:
  replicas: 5
  revisionHistoryLimit: 2
  selector:
    matchLabels:
      app: colorapi
  template:
    metadata:
      labels:
        app: colorapi
    spec:
      containers:
      - name: colorapi
        image: particule/simplecolorapi:1.0
        imagePullPolicy: Always
        ports:
        - name: web
          containerPort: 5000
---
apiVersion: v1
kind: Service
metadata:
  name: colorapi
spec:
  ports:
  - port: 80
  selector:
    app: colorapi
  type: LoadBalancer
```


# ArgoCD

Comme son nom l'indique, ArgoCD gère la partie Continuous Delivery, il permet entre
autres de déployer des versions spécifiques d'applications et de réconcilier
l'état demandé avec l'état actuel du cluster. ArgoCD supporte
[Helm](https://helm.sh/), [Ksonnet](https://ksonnet.io/),
[Jsonnet](https://jsonnet.org/) et [Kustomize](https://kustomize.io/) en plus
des manifests Kubernetes classiques. Nous allons utiliser la partie manifests
Kubernetes classiques pour notre exemple.


Je vous laisse suivre le [getting started de la doc
officielle](https://argoproj.github.io/argo-cd/getting_started/) pour déployer
Argo sur votre cluster Kubernetes et installer la CLI ArgoCD. On peut ensuite
déployer la première application sur ArgoCD.

```console
$ argocd app create colorapi --repo https://github.com/particuleio/demo-concourse-flux.git --path deploy --dest-server https://kubernetes.default.svc --dest-namespace default
$ argocd app sync colorapi
$ kubectl get pod
NAME                          READY   STATUS    RESTARTS   AGE
colorapi-7ccb9d965b-8pr54   1/1     Running   0          22s
colorapi-7ccb9d965b-9vtmp   1/1     Running   0          22s
colorapi-7ccb9d965b-c7jkf   1/1     Running   0          22s
colorapi-7ccb9d965b-klt7q   1/1     Running   0          22s
colorapi-7ccb9d965b-s2ftc   1/1     Running   0          22s
```

Pour vérifier que ArgoCD fonctionne bien, nous allons appliquer une
modification sur le nombre de réplicas dans notre Deployment, puis pousser nos
changements. Argo peut tracker différentes choses, branches, tag, commit etc. Si
 jamais vous tracker un
tag git, pensez à l'update sinon ArgoCD ne verra pas la mise à jour

<https://argoproj.github.io/argo-cd/user-guide/tracking_strategies/>

Le poll a
lieu toutes les 3 min, vous devriez vite voir vos nouveaux réplicas arriver sur
votre cluster.

Rien de bien nouveau, on vous avait déjà [présenté Flux
CD](https://particule.io/blog/cicd-concourse-flux/) qui fait,
jusque là, exactement la même chose.

Passons à un vrai update applicatif.

# Argo Rollout

Autre composant de la suite Argo : [Argo
Rollout](https://github.com/argoproj/argo-rollouts). Il augmente les stratégies
de déploiement fournies de base dans Kubernetes et ajoute la fonctionnalité
de *Canary Deployment* ainsi que *Blue/Green Deployment*. Et ici on va
s'intéresser au Canary Deployment. Il n'y a pas vraiment de définition précise
pour un Canary Deployment, le concept de base c'est qu'on va rediriger une
proportion du trafic de la version stable (`baseline`) de l'application vers la nouvelle
version (`canary`). Ensuite c'est chacun sa sauce, on peut augmenter de 10% en 10%
pendant des heures ou passer directement à 90% en 5 min. Comme vous le sentez.
Généralement pendant le rolling update, on va effectuer des tests sur la
nouvelle version pour vérifier que les réponses sont correctes.

Déployons Argo Rollout :

```console
$ kubectl create namespace argo-rollouts
$ kubectl apply -n argo-rollouts -f https://raw.githubusercontent.com/argoproj/argo-rollouts/stable/manifests/install.yaml
```

Argo Rollout apporte notamment une CustomResourceDefinition qui vient
surcharger la ressource Deployment : **Rollout**. Pour l'utiliser c'est très
simple, on va juste mettre à jour notre ressource Deployment en changeant sa
version et son kind par ces valeurs :

```
apiVersion: argoproj.io/v1alpha1 # Changed from apps/v1
kind: Rollout # Changed from Deployment
```

On commit cette modification et on laisse ArgoCD mettre à jour notre
application. Rien ne devrait changer.

## Rollout strategy

La ressource Rollout permet d'augmenter les possibilités offertes par la spec
`strategy`. C'est ici qu'on va y définir les paramètres de notre Canary.

```yaml
  strategy:
    canary:
      steps:
      - setWeight: 20
      - pause:
          duration: "30s"
      - setWeight: 50
      - pause:
          duration: "30s"
```

Il y aura 4 étapes à notre rolling update :

- On redirige 20% du trafic vers notre nouvelle version
- On attend 30s
- On redirige 50% du trafic vers notre nouvelle version
- On attend 30s

La dernière étape, implicite, fait passer 100% du trafic sur la nouvelle version
de l'application.

Contrairement à un Ingress qui peut réellement répartir son trafic entre
plusieurs Services, ici nous n'avons qu'un Service. Cette répartition
proportionelle du trafic se fait par une représentation plus ou moins
importante d'un des deux ReplicaSet et par l'utilisation d'un mécanisme de
round-robin. OK, moi je triche un peu, mais Argo Rollout saurait faire ça
nativement. Il possède en effet des [mécanismes de trafic management, Istio,
Nginx et ALB sont
supportés](https://argoproj.github.io/argo-rollouts/features/traffic-management/).

Updatons notre Rollout en changeant le tag de notre image :

```console
$ sed -i 's/1.0/2.0/g' deploy/helloworld.yml
$ git commit -am "bump: 2.0"
$ git push
$ argocd app sync colorapi
TIMESTAMP                  GROUP              KIND         NAMESPACE                  NAME    STATUS    HEALTH        HOOK  MESSAGE
2020-04-25T11:40:32+02:00  argoproj.io     Rollout           default              colorapi    Synced   Healthy
2020-04-25T11:40:32+02:00                  Service           default              colorapi    Synced   Healthy
2020-04-25T11:40:32+02:00  argoproj.io  AnalysisTemplate     default              webcheck  OutOfSync

Name:               colorapi
Project:            default
Server:             https://kubernetes.default.svc
Namespace:          default
URL:                https://argo_url.tld/applications/colorapi
Repo:               https://github.com/particuleio/demo-concourse-flux
Target:             argocd
Path:               deploy
SyncWindow:         Sync Allowed
Sync Policy:        Automated (Prune)
Sync Status:        OutOfSync from argocd (95662aa)
Health Status:      Healthy

Phase:              Running
Start:              2020-04-25 11:40:34 +0200 CEST
Finished:           <nil>
Duration:           1s

GROUP        KIND              NAMESPACE  NAME      STATUS     HEALTH   HOOK  MESSAGE
             Service           default    colorapi  Synced     Healthy
argoproj.io  AnalysisTemplate  default    webcheck  OutOfSync
argoproj.io  Rollout           default    colorapi  Synced     Healthy
```

Voici ce qu'il doit se passer :

- Un nouveau ReplicaSet (RS) est crée avec 2 pods désirés, il y a donc 2 pods
  Canary sur 8 (16% ~= 20%)
- Pendant 30 sec, rien ne bouge
- Un nouveau pod Canary est crée et trois pods Baseline sont détruits, il y a
  donc 3 pods Canary sur 6 (50%)
- Pendant 30 sec, rien ne bouge
- Les trois derniers pods Baseline sont détruits et 3 nouveaux pods Canary
  apparaissent finissant le rolling update


Si on suit ce déroulement en curlant notre application, on observe clairement
le basculement :

```console
$ while true; do curl $monapp | jq .color; sleep 0.5; done
"red"
"red"
"red"
"red"
"red"
"red"
"red"
# début des 20%
"blue"
"red"
"red"
"red"
"red"
"red"
"blue"
"red"
"red"
"red"
"blue"
"blue"
"red"
"red"
"red"
"red"
"red"
"red"
"red"
# début des 50%
"blue"
"red"
"blue"
"red"
"red"
"blue"
"blue"
"blue"
"red"
"blue"
"red"
"blue"
"blue"
"red"
"red"
"blue"
"blue"
"red"
"red"
# Fin du rolling update
"blue"
"blue"
"blue"
"blue"
"blue"
"blue"
"blue"
```

Ce rolling-update peut aussi être effectué directement depuis votre CLI avec le
[plugin argo de
kubectl](https://argoproj.github.io/argo-rollouts/features/kubectl-plugin/).
Vous pouvez déclencher un rolling update avec la commande :

```console
$ kubectl argo rollouts set image colorapi "*=particule/simplecolorapi:2.0"
rollout "colorapi" image updated
```

Et ce plugin offre aussi la possibilité de suivre le rolling update en temps
réel avec un affichage extrêmement sympathique :

```console
$ kubectl argo rollouts get rollout colorapi -w
Name:            colorapi
Namespace:       default
Status:          ✔ Healthy
Strategy:        Canary
  Step:          4/4
  SetWeight:     100
  ActualWeight:  100
Images:          particule/simplecolorapi:1.0 (stable)
Replicas:
  Desired:       3
  Current:       3
  Updated:       3
  Ready:         3
  Available:     3

NAME                                  KIND         STATUS        AGE    INFO
⟳ colorapi                            Rollout      ✔ Healthy     5h52m
├──# revision:32
│  ├──⧉ colorapi-66f9756599           ReplicaSet   ✔ Healthy     10m    stable
│  │  ├──□ colorapi-66f9756599-p4kfl  Pod          ✔ Running     4m6s   ready:1/1
│  │  ├──□ colorapi-66f9756599-lqnsn  Pod          ✔ Running     3m32s  ready:1/1
│  │  └──□ colorapi-66f9756599-554wc  Pod          ✔ Running     2m58s  ready:1/1
│  └──α colorapi-66f9756599-32        AnalysisRun  ✔ Successful  4m6s   ✔ 30,⚠ 12
├──# revision:31
│  ├──⧉ colorapi-7d458c8cd8           ReplicaSet   • ScaledDown  5m36s
│  └──α colorapi-7d458c8cd8-31        AnalysisRun  ✔ Successful  5m36s  ✔ 30
├──# revision:30
   ├──⧉ colorapi-59b5ddb84f           ReplicaSet   • ScaledDown  7m1s
   └──α colorapi-59b5ddb84f-30        AnalysisRun  ✔ Successful  7m     ✔ 30
```

## Analysis Run

Mais ce qui est intéressant c'est de pouvoir observer notre rolling-update et
pouvoir prendre une décision le concernant. Si le comportement de notre Canary
n'est pas correct, on doit pouvoir automatiquement revenir en arrière.

Pour cela on utilise une nouvelle ressource `AnalysisRun`. On va utiliser la
ressource `AnalysisTemplate` pour décrire nos test et on va modifier légèrement
notre Rollout pour y déclarer l'utilisation de notre AnalysisRun.

```yaml
strategy:
    canary:
      analysis:
        templates:
        - templateName: webcheck
      args:
      - name host
        value: colorapi
      steps:
      - setWeight: 20
      - pause:
          duration: "30s"
      - setWeight: 50
      - pause:
          duration: "30s"
---
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: webcheck
spec:
  args:
  - name: host
  metrics:
  - name: webcheck
    failureLimit: 1
    interval: 5
    successCondition: result == "ok"
    provider:
      web:
        # paceholders are resolved when an AnalysisRun is created
        url: "http://{{args.host}}/"
        jsonPath: "{$.status}"
```

Quelques explications. Tout d'abord détaillons les nouveautés  de notre `Rollout`.
La première c'est le paramètre `analysis`, il permet de spécifier
l'AnalysisTemplate que nous allons utiliser, dans notre cas cette analyse va
tourner indéfiniment jusqu'à ce que notre Rollout soit accompli ou que
l'analyse échoue. On peut aussi la déclencher à partir d'une certaine étape
du Rollout. On spécifie aussi un argument `host = colorapi`, cela va nous
servir à diriger notre analyse, dans notre cas, `colorapi` c'est le nom de
notre Service.

Pour l'`Analysis`. Il existe plusieurs
[providers](https://argoproj.github.io/argo-rollouts/features/analysis/) et
nous avons choisi `web` puisqu'il nous permet facilement de se baser sur
l'output json d'un webservice pour déterminer si notre test est successful ou
non. Notre test consiste donc en l'analyse de la valeur de la clé `status`, si
c'est "ok" c'est bon, sinon c'est fail. Le
test va se dérouler toutes les 5 secondes et notre marge d'erreur est d'un seul
fail. Dès qu'un second se produira, notre Analysis passera en fail et notre
rolling-update sera arrêté et un rollback se mettra en route.

Démonstration avec l'update vers notre image non fonctionnelle.

```console
$ kubectl argo rollouts set image colorapi "*=particule/simplecolorapi:3.0"
rollout "colorapi" image updated

$ while true; do curl $monapp | jq .color; sleep 0.5; done
# Début du test, tout se passe bien
"red"
"red"
"red"
"red"
"red"
"red"
"red"
# Début des 20%, les ennuis arrivent
"black"
"red"
"red"
"black"
"red"
"black"
"red"
"red"
"red"
"red"
"red"
"black"
"black"
# Plus de 1 erreur ont eu lieu, le test a échoué, on rollback !
"red"
"red"
"red"
"red"
"red"
"red"
"red"
"red"
"
```

Le résultat final de notre Rollout ressemble à ceci :

```console
$ kubectl argo rollouts get rollout colorapi
Name:            colorapi
Namespace:       default
Status:          ✖ Degraded
Strategy:        Canary
  Step:          0/2
  SetWeight:     0
  ActualWeight:  0
Images:          particule/simplecolorapi:1.0 (stable)
Replicas:
  Desired:       3
  Current:       3
  Updated:       0
  Ready:         3
  Available:     3

NAME                                            KIND         STATUS        AGE  INFO
⟳ colorapi                                      Rollout      ✖ Degraded    30h
├──# revision:34
│  ├──⧉ colorapi-7d458c8cd8                     ReplicaSet   • ScaledDown  28h  canary
│  └──α colorapi-7d458c8cd8-34                  AnalysisRun  ✖ Failed      35m  ✔ 1,✖ 2

```

Notre état est dégradé car nous avons demandé à avoir l'image 3.0 mais celle ci
a du être rollback du aux 2 erreurs de notre `AnalysisRun`. Pour repasser en
`Healthy`, il suffit de set à nouveau l'image en version `1.0`

Mais ce qui compte c'est que notre rolling-update a bien été arrêté et que nous
avons empêché une application corrompue d'atterrir en production !

# Conclusion

Nous n'avons fait qu'effleurer les possibilités d'Argo, notre métrique n'avait
pas beaucoup de sens, notre application non plus, mais ces exemples sont
suffisants pour comprendre toute l'importance d'utiliser tous les pratiques du
GitOps pour déployer sûrement et sereinement vos applications en production.


[**Romain Guichard**](https://www.linkedin.com/in/romainguichard)
