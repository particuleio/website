---
Title: Canary deployment et trafic management avec Nginx
Date: 2020-05-16
Category: Kubernetes
Summary: Trafic management lors d'un Canary deployment avec Argo Rollout et Nginx
Author: Romain Guichard
image: images/argo/argo-logo.png
imgSocialNetwork: images/og/canary-nginx.png
lang: fr
---

Cette article fait écho à deux de nos précédents articles. [Le premier
présentait Argo et son adoption par la
CNCF](https://particule.io/blog/cncf-argo/) et [le second démontrait
l'utilisation d'ArgoCD et de Argo-Rollout lors d'un Canary
deployment](https://particule.io/blog/argocd-canary/). On se propose de
reprendre les mêmes bases que ce dernier article mais d'aller un peu plus loin
dans la gestion de votre Canary deployment et notamment de gérer plus finement
et intelligement le trafic entre vos pods stables et vos pods Canary.

### Rappels

Argo est une suite d'outils orientés GitOps [récemment adopté par la
CNCF](https://www.cncf.io/projects/). Les composants de la suite sont les
suivants :

- ArgoCD
- Argo Workflow
- Argo Rollout
- Argo Event

GitOps ? GitOps est un terme inventé et popularisé par
[Weaveworks](https://www.weave.works). GitOps repose sur 4 principes :

- Votre système (stack applicative, infrastructure, etc) est décrit
  déclarativement. Les manifests Kubernetes sont un exemple de description
déclarative. On oppose le fait de déclarer notre système par un fichier texte
(déclaratif) au fait de le déclarer par des commandes (impératif).
- L'état désiré du système est stocké dans Git et Git est donc considéré comme
  votre **unique source de vérité**. Grâce aux fonctions natives de Git et aux
fonctions ajoutées (par les repositories managés comme GitHub) comme les Pull
Requests, vous êtes en mesure de contrôler finement cet état.
- Les changements acceptés dans Git sont automatiquement appliqués au système.
  On y sépare ici le fait d'apporter des modifications à l'état désiré et le fait
de les appliquer. Ces deux fonctions sont séparées. Le contrôle au sein de Git
est donc absolument primordial.
- La différence entre l'état désiré et l'état réel est monitorée et différents
  mécanismes tentent continuellement de réduire cette différence.

Je vous invite à reparcourir notre article si vous souhaitez vous rafraichir la
mémoire sur les sous projets Argo.

Et un Canary deployment c'est quoi déjà ?

Il n'y a pas vraiment de définition précise
pour un Canary deployment, le concept de base c'est qu'on va rediriger une
proportion du trafic de la version stable (`stable`) de l'application vers la nouvelle
version (`canary`). Ensuite c'est chacun sa sauce, on peut augmenter de 10% en 10%
pendant des heures ou passer directement à 90% en 5 min. Comme vous le sentez.
Généralement pendant le rolling update, on va effectuer des tests sur la
nouvelle version pour vérifier que les réponses sont correctes.


Je ne redétails par l'installation d'ArgoCD et d'Argo-Rollout, je vous laisse
vous reporter à [notre article pour
cela](https://particule.io/blog/argocd-canary/).


### Modification de notre Canary deployment

Un Canary deployment consiste donc à rediriger un certain pourcentage du trafic vers de
nouveaux pods puis d'augmenter ce pourcentage. Des tests peuvent être effectués
tout au long du rolling-update et peuvent permettre de valider ou d'annuler
l'update.

Dans notre précédent article, nous avions un peu triché. En effet les services
Kubernetes ne permettent pas réellement de répartir le trafic en fonction d'un
pourcentage, ils ne peuvent que l'imiter. En effet, avec les services
Kubernetes, le seul moyen de contrôler
la quantité de trafic envoyée à des versions différentes d'une application est
de manipuler le nombre de pods de ces versions. Si on a 6 pods en v1 et 4 pods
en v2, 60% du trafic ira naturellement vers la v1 et 40% sur la v2.

Globalement ce manque est comblé par les services mesh. Et certains/la plupart
d'entre eux implémentent des fonctions d'Ingress Controller. On peut donc
utiliser des ressources Ingress pour décider complètement artificiellement de
diriger 30% du trafic vers les pods v2 même si ceux ci ne représentent
absolument pas 30% des pods en fonctionnement.

Argo-Rollout supporte quatre services mesh et/ou Ingress Controller pour effectuer ce trafic management :

- Istio
- Nginx Ingress Controller
- AWS ALB Ingress Controller
- Service Mesh Interface (SMI)

Répartir le trafic selon des pourcentages arbitraires est une des possibilités
offertes par les solutions trafic management. Il est aussi possible d'effectuer un
mirroring de notre trafic, ainsi tout le trafic vers les pods Stable est
dupliqué vers les pods Canary mais les réponses de ces pods sont ignorées. On
peut aussi contrôler la destination du trafic en fonction d'un header HTTP.

Nous allons utiliser **Nginx Ingress Controller** pour notre exemple. Et je
supposerai que vous avez l'avez déjà installé, sinon je vous redirige vers [la
documentation](https://kubernetes.github.io/ingress-nginx/).

Modifions maintenant notre Rollout pour y inclure les nouvelles spécificités et
ajoutons un Service et un Ingress.

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: colorapi
  labels:
    app: colorapi
spec:
  strategy:
    maxSurge: 10
    canary:
      canaryService: canary-colorapi
      stableService: colorapi
      trafficRouting:
        nginx:
           stableIngress: primary-ingress
           additionalIngressAnnotations:
             canary-by-header: X-Canary
             canary-by-header-value: true
      steps:
      - setWeight: 25
      - pause:
          duration: "30s"
      - setWeight: 50
      - pause:
          duration: "30s"
  replicas: 10
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
    targetPort: 5000
  selector:
    app: colorapi
  type: ClusterIP
---
apiVersion: v1
kind: Service
metadata:
  name: canary-colorapi
spec:
  ports:
  - port: 80
    targetPort: 5000
  selector:
    app: colorapi
  type: ClusterIP
---
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  namespace: default
  name: primary-ingress
spec:
  rules:
  - host: colorapi.particule.tech
    http:
      paths:
      - backend:
          serviceName: colorapi
          servicePort: 80
```

Nous avons donc créer un second Service `canary-colorapi` qui servira de
Service pour nos pods Canary. Rien à dire sur l'Ingress mis à part que celui ci
ne sert que le service Stable.

En revanche, plusieurs changements pour le Rollout :
```
canary:
   canaryService: canary-colorapi
   stableService: colorapi
   trafficRouting:
     nginx:
       stableIngress: primary-ingress
       additionalIngressAnnotations:
         canary-by-header: X-Canary
         canary-by-header-value: true
```

On indique tout d'abord à Argo lesquels de nos Services serviront les pods
Canary des pods Stable. Cette partie était optionelle dans notre précédent
article. Puis viennent les instructions concernant le trafficRouting. On spécifie
l'ingress Stable, celui que nous avons crée il y a quelques temps. Le dernier
paramètre donne accès aux fonctions propres aux services mesh / Ingress
Controller dont je parlais plus haut, celle ci permet de forcer le trafic vers
nos Canary si un header HTTP avec la clé `X-Canary` possède la valeur `true`.

On remarquera que j'ai supprimé la partie `Analysis`, ce n'est pas le but de
l'exercice ici.

Reprenons notre application et ses trois releases, bien que deux suffiront ici.

- `1.0` en mettant `color` à `red`
- `2.0` en mettant `color` à `blue`
- `3.0` en mettant `color` à `black` et `status` à `nok`

### Rolling-update !

Appliquons un changement de version et observons le comportement :

```
$ kubectl argo rollouts set image colorapi "*=particule/simplecolorapi:2.0"
$ kubectl argo rollouts get rollout colorapi -w
Name:            colorapi
Namespace:       default
Status:          ॥ Paused
Strategy:        Canary
  Step:          1/4
  SetWeight:     25
  ActualWeight:  20
Images:          particule/simplecolorapi:1.0 (stable)
                 particule/simplecolorapi:2.0 (canary)
Replicas:
  Desired:       12
  Current:       15
  Updated:       3
  Ready:         15
  Available:     15

NAME                                  KIND        STATUS        AGE    INFO
⟳ colorapi                            Rollout     ॥ Paused      3d1h
├──# revision:16
│  └──⧉ colorapi-59b5ddb84f           ReplicaSet  ✔ Healthy     3d1h   canary
│     ├──□ colorapi-59b5ddb84f-2cbcc  Pod         ✔ Running     22s    ready:1/1
│     ├──□ colorapi-59b5ddb84f-8jxhv  Pod         ✔ Running     22s    ready:1/1
│     └──□ colorapi-59b5ddb84f-d4prs  Pod         ✔ Running     22s    ready:1/1
├──# revision:15
   └──⧉ colorapi-c7f556754            ReplicaSet  ✔ Healthy     3d1h   stable
      ├──□ colorapi-c7f556754-22pgd   Pod         ✔ Running     2d     ready:1/1
      ├──□ colorapi-c7f556754-lcx94   Pod         ✔ Running     2d     ready:1/1
      ├──□ colorapi-c7f556754-xxt6m   Pod         ✔ Running     2d     ready:1/1
      ├──□ colorapi-c7f556754-vn8hl   Pod         ✔ Running     2d     ready:1/1
      ├──□ colorapi-c7f556754-hbwq4   Pod         ✔ Running     2d     ready:1/1
      ├──□ colorapi-c7f556754-97bdr   Pod         ✔ Running     2d     ready:1/1
      ├──□ colorapi-c7f556754-9zvzd   Pod         ✔ Running     2d     ready:1/1
      ├──□ colorapi-c7f556754-9jzif   Pod         ✔ Running     2d     ready:1/1
      ├──□ colorapi-c7f556754-eorf8   Pod         ✔ Running     2d     ready:1/1
      ├──□ colorapi-c7f556754-dr6rw   Pod         ✔ Running     2d     ready:1/1
      ├──□ colorapi-c7f556754-tsj7j   Pod         ✔ Running     2d     ready:1/1
      └──□ colorapi-c7f556754-vl4wl   Pod         ✔ Running     2d     ready:1/1

$ kubectl describe ingress
Name:             colorapi-primary-ingress-canary
Namespace:        default
Address:          a.b.c.d
Default backend:  default-http-backend:80 (<error: endpoints "default-http-backend" not found>)
Rules:
  Host                   Path  Backends
  ----                   ----  --------
  colorapi.particule.tech
                            canary-colorapi:80 (100.64.0.9:5000,100.65.128.8:5000,100.65.128.9:5000)
Annotations:             nginx.ingress.kubernetes.io/canary: true
                         nginx.ingress.kubernetes.io/canary-by-header: X-Canary
                         nginx.ingress.kubernetes.io/canary-by-header-value: true
                         nginx.ingress.kubernetes.io/canary-weight: 25
Events:
  Type    Reason  Age                  From                      Message
  ----    ------  ----                 ----                      -------
  Normal  UPDATE  50s (x68 over 3d1h)  nginx-ingress-controller  Ingress default/colorapi-primary-ingress-canary

```

Que constate t-on ?

Comme prévu par nos steps, 25% du trafic est envoyé vers notre Canary. Mais on
voit bien que les pods Canary ne représentent pas 25% du total, notre Rollout
nous l'indique ils représentent 20% du total. Ce 20% correspond au poids
"visible" par le Rollout, il n'a pas conscience de l'Ingress situé devant lui
effectuant le trafic management. On remarque aussi que les pods Stable n'ont
absolument pas été scale down, en effet, comme le trafic est géré
indépendamment par notre Ingress Controller, nous n'avons pas besoin
d'équilibrer les deux ReplicaSets.

Néanmoins, ce mécanisme demande un certain équilibre.
En répartissant notre trafic de la sorte, il faut s'assurer à tout moment que
nos ReplicaSets ne vont pas se retrouver surchargés, c'est la raison pour
laquelle le ReplicaSet Stable reste totalement scale up jusqu'à la fin du
rollout. Le nombre de pods Canary est lui déterminé de façon à ce qu'il puisse
absorber toute le trafic reçu. Leur nombre est calculé par la multplication du
nombre de réplicas du ReplicatSet Stable par le dernier *setWeight* appliqué.
Dans notre cas, il y a 12 pods dans le ReplicaSet Stable et notre *setWeight*
est à 25%, ce qui nous donne 3 pods dans notre ReplicaSets Canary. Le compte
est bon.

Et notre Ingress alors ? On peut constater que les annotations ont été
proprement ajoutées à ce nouvel Ingress qui redirige donc bien 25% du trafic
vers notre backend `canary-colorapi`.


### Header-based routing

A tout moment pendant le rollout, vous pouvez accéder directement aux pods
Canary en utilisant le header HTTP :
```
$ curl -H "Host: colorapi.particule.tech" -H "X-Canary: true" a.b.c.d
{
    "color": "red",
    "status": "ok"
}

```

Très simple d'utilisation et cela donne un excellent endpoint pour effectuer
des Analysis et des Experiment.

### Conclusion

Si on laisse notre rollout se poursuivre, nous passons à 50% de trafic pour le
Canary. Nos pods Canary ne représenteront toujours pas 50% des pods de
l'application (ils seront 6 sur 18 si vous avez bien suivi, donc seulement
30%) puis à la dernière étape ce pourcentage passera à 0, tous les pods Stable
seront scale down à 0 et nos pods Canary deviendront nos nouveaux pods Stable,
achevant ainsi notre rollout.


[**Romain Guichard**](https://www.linkedin.com/in/romainguichard)
