---
Title: Automatique image update dans Git avec FluxCD
Date: 2021-02-03
Category: Kubernetes
Summary: "Cette fonction avait disparu depuis FluxCD v2 mais elle est désormais
de retour et permet de tracker automatiquement les updates d'image !"
Author: Romain Guichard
image: images/thumbnails/flux-horizontal-color.png
imgSocialNetwork: images/og/flux-image-update.png
lang: fr
---

Cela fait longtemps que nous n'avons pas parlé de Gitops sur ce blog. C'est un
sujet que nous avons déjà largement couvert et je vous redonne nos principaux
articles sur le sujet :

- [Kubernetes Kustomize avec FluxCD](https://particule.io/blog/flux-kustomize/)
- [Canary deployment et trafic management avec
  Nginx](https://particule.io/blog/argorollout-canary-nginx/)
- [Canary Deployment avec ArgoCD](https://particule.io/blog/argocd-canary/)
- [Semantic release avec Kubernetes et
  FluxCD](https://particule.io/blog/flux-semver/)
- [Continuous delivery avec FluxCD et
  Concourse-CI](https://particule.io/blog/cicd-concourse-flux/)

## Petit rappel sur Gitops

Gitops est un ensemble d'outil et de pratiques pour déployer vos applications
et infrastructures. Grâce à l'infrastructure as code, votre infrastructure
comme vos applications sont définis par du code stocké dans Git. Gitops utilise
ses fichiers déclaratifs comme votre **source unique de vérité**. Il permet
d'assurer une synchronisation parfaite entre l'état désiré (stocké dans Git) et
l'état réel (typiquement votre cluster Kubernetes).

Pourquoi c'est bien ?

Tout d'abord vous n'avez plus à vous soucier de gérer votre cluster avec
`kubectl`, l'agent Gitops (on reviendra sur les solutions) se charge
d'appliquer les changements que vous apportez à Git. Utiliser Git est donc la
seule chose que vous devez maîtriser. Grâce aux process de review, au
PR, MR etc, vous êtes en mesure de contrôler précisemment ce qui est appliqué à
votre cluster.

Au final vous avez les 4 principes de Gitops :

- Votre système est défini déclarativement
- L'état désiré de votre système est stocké dans Git qui constitue votre unique
  source de vérité
- Les changements sont contrôlés et appliqués dès leur validation
- Un process se charge d'assurer la synchronisation constante entre état réel
  et état désiré

Les deux principales solutions implémentant ces principes sont
[FluxCD](https://fluxcd.io) et [ArgoCD](https://argoproj.github.io/argo-cd/).
Les deux sont membres de la CNCF. En terme de développement, FluxCD
suit les spécifications du Gitops Toolkit tandis que ArgoCD suit celles du
Gitops Engine.

On a déjà écrit sur les deux technologies et si aujourd'hui on en parle à
nouveau c'est car une nouvelle feature que tout le monde attendait
 vient d'arriver en alpha : **la mise à jour automatique des images dans Git**.

## Ça existait pas déjà ?

Tout à fait, mais dans FluxCD v1, depuis la v2 cette fonction avait disparu
mais faisait parti des priorités sur la roadmap.

Le comportement normal de FluxCD est de surveiller votre répo Git et
d'appliquer les modifications que vous y apportez. Si vous supprimez par erreur
un Deployment, FluxCD va le recréer dans son process de réconciliation. FluxCD
v1 permettait aussi de surveiller les nouvelles versions de l'image utilisée
par vos conteneurs. FluxCD était capable de surveiller une container registry,
y détecter les nouveaux tags d'une image puis d'aller mettre à jour le
nouveau tag dans Git pour ensuite laisser le processus de réconciliation faire
son travail en mettant à jour vos conteneurs sur Kubernetes. Grâce aux
annotations, FluxCD permettait de tracker précisemment les nouvelles versions
en fonction de regex ou de semver. On pouvait par exemple décider de déployer
toutes les versions en `1.0.x` mais pas les autres. Nous avons abordé ce point
dans [un précédent article](https://particule.io/blog/flux-semver/)

On considère parfois que ce comportement sort du cadre de Gitops puisque la
container registry devient quasiment une deuxième source de vérité. C'est
d'ailleurs pour cela qu'Argo n'implémente pas cette fonctionnalité.

Elle avait disparu de FluxCD v2 mais est depuis quelques jours revenue dans une
version alpha.

## Mise en place

On va tout d'abord bootstraper un environement Flux en suivant la doc puis on
viendra le modifier pour prendre en compte la nouvelle fonctionnalité.

Pour bootstraper Flux, vous aurez besoin d'un token GitHub (ou Gitlab) donnant
les droits aux permissions `repo` :

![PAT](/images/flux/github-pat.png)

```console
$ curl -s https://toolkit.fluxcd.io/install.sh | sudo bash
$ flux check --pre
$ export GITHUB_TOKEN=YOUR-TOKEN
$ flux bootstrap github --owner=rguichard --repository=fluxcd-demo --path=clusters/fluxcd-demo --personal
► connecting to github.com
✔ repository cloned
✚ generating manifests
✔ components are up to date
► installing components in flux-system namespace
namespace/flux-system created
customresourcedefinition.apiextensions.k8s.io/alerts.notification.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/buckets.source.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/gitrepositories.source.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/helmcharts.source.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/helmreleases.helm.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/helmrepositories.source.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/kustomizations.kustomize.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/providers.notification.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/receivers.notification.toolkit.fluxcd.io created
serviceaccount/helm-controller created
serviceaccount/kustomize-controller created
serviceaccount/notification-controller created
serviceaccount/source-controller created
clusterrole.rbac.authorization.k8s.io/crd-controller-flux-system created
clusterrolebinding.rbac.authorization.k8s.io/cluster-reconciler-flux-system created
clusterrolebinding.rbac.authorization.k8s.io/crd-controller-flux-system created
service/notification-controller created
service/source-controller created
service/webhook-receiver created
deployment.apps/helm-controller created
deployment.apps/kustomize-controller created
deployment.apps/notification-controller created
deployment.apps/source-controller created
networkpolicy.networking.k8s.io/allow-scraping created
networkpolicy.networking.k8s.io/allow-webhooks created
networkpolicy.networking.k8s.io/deny-ingress created
Waiting for deployment "source-controller" rollout to finish: 0 of 1 updated replicas are available...
deployment "source-controller" successfully rolled out
deployment "kustomize-controller" successfully rolled out
Waiting for deployment "helm-controller" rollout to finish: 0 of 1 updated replicas are available...
deployment "helm-controller" successfully rolled out
Waiting for deployment "notification-controller" rollout to finish: 0 of 1 updated replicas are available...
deployment "notification-controller" successfully rolled out
✔ install completed
► configuring deploy key
✔ deploy key configured
► generating sync manifests
► applying sync manifests
◎ waiting for cluster sync
✔ bootstrap finished
```

Contrairement à Flux v1 qui était composé d'un seul controlleur, Flux v2
utilise le Gitops toolkit qui est composé de plusieurs éléments sous forme de
CRD :

- Source Controller
- Kustomize Controller
- Helm Controller
- Notification Controller
- Image Automation Controller

<https://toolkit.fluxcd.io/components/>

C'est bien évidemment le dernier qui va ensuite nous intéresser.

Tous ces composants sont installés et vous pouvez dès à présent commiter une
ressources Kubernetes dans le repository crée par Flux pour vous
(`fluxcd-demo` chez moi) et vous devriez, 1 min plus tard, voir apparaitre la
ressources dans votre cluster Kubernetes.

## Image automation

Le controller Image Automation n'est en fait pas installé par défaut (parce que
c'est une fonction encore en alpha) et vous devez reconfigurer Flux. La
commande `flux bootstrap` est idempotente et vous pouvez donc juste relancer la
même commande en y ajoutant deux composants supplémentaires :

```console
--components-extra=image-reflector-controller,image-automation-controller
```

Pour simuler de nouvelles images, nous allons simplement les re-taguer :

```console
$ docker tag particule/helloworld particule/helloworld:v1.0.0
$ docker tag particule/helloworld particule/helloworld:v1.1.0
$ docker tag particule/helloworld particule/helloworld:v2.0.0
```

Pour tracker une image, Flux utilise la CRD ImageRepository :

```yaml
apiVersion: image.toolkit.fluxcd.io/v1alpha1
kind: ImageRepository
metadata:
  name: helloworld
  namespace: flux-system
spec:
  image: particule/helloworld
  interval: 1m0s
```

Il faut ensuite utiliser la CRD ImagePolicy pour spécifier les paramètres de
tracking.

```yaml
apiVersion: image.toolkit.fluxcd.io/v1alpha1
kind: ImagePolicy
metadata:
  name: helloworld
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: helloworld
  policy:
    semver:
      range: '>= 1.0.0 <2.0.0'
```

Je choisi ici de tracker toutes les versions situées entre la version majeure 1
et la version majeure 2. Seules `particule/helloworld:1.0.0` et
`particule/helloworld:1.1.0` devraient donc être concernées par l'update. La
version `particule/helloworld:2.0.0` ne devraient pas déclencher de mise à
jour.

Ces deux éléments permettent de mettre en place le scan de la container
registry et des
nouvelles versions mais ne met pas à jour votre repository git.

Vous pouvez vérifier que le scan fonctionne bien :

```console
$ flux get image policy helloworld
NAME      	READY	MESSAGE                                                       	LATEST IMAGE
helloworld	True 	Latest image tag for 'particule/helloworld' resolved to: 1.1.0	particule/helloworld:1.1.0
$ flux get image repository helloworld
NAME      	READY	MESSAGE                       	LAST SCAN           	SUSPENDED
helloworld	True 	successful scan, found 11 tags	2021-02-03T23:45:03Z	False
```

On voit que la dernière image que j'ai poussée est la `1.1.0`.

Configurons maintenant l'update de l'image. Pour cela Flux va avoir besoin de
commit dans notre repository git pour lancer le processsus de réconciliation.

Deux choses à faire ici, créer la ressource ImageUpdateAutomation et modifier
notre Deployment pour indiquer à Flux quelle image il doit réellement modifier.
Pour cela dans votre application, il faut apposer un marqueur `#
{"$imagepolicy": "POLICY_NAMESPACE:POLICY_NAME"}` à l'image.

```
spec:
  containers:
  - name: container
    image: particule/helloworld:1.0.0 # {"$imagepolicy": "flux-system:helloworld"}
```

```yaml
apiVersion: image.toolkit.fluxcd.io/v1alpha1
kind: ImageUpdateAutomation
metadata:
  name: helloworld
  namespace: flux-system
spec:
  checkout:
    branch: main
    gitRepositoryRef:
      name: helloworld
  commit:
    authorEmail: fluxcdbot@particule.io
    authorName: fluxcdbot
    messageTemplate: 'update image'
  interval: 1m0s
  update:
    strategy: Setters
```

On voit que vous avez la possibilité de commit dans une autre branche que main.
L'idée serait probablement de valider le merge dans main via une Pull Request.
Vérifiez bien que la Deploy Key dans votre repository Git possède bien les
droits d'écriture. Si ce n'est pas le cas, vous pouvez récupérer la clé
publique utilisée par Flux pour la reconfigurer dans Github :

```
$ kubectl -n flux-system get secret flux-system -o json | jq '.data."identity.pub"' -r | base64 -d
```

On applique et on attend que la magie s'opère.

```console
$ kubectl get deploy helloworld -o json | jq -r '.spec.template.spec.containers[0].image'
particule/helloworld:1.1.0
```

Notre Deployment a bien été updaté avec la nouvelle image et notre repository
est lui aussi à jour.

```console
commit 75ba609fa4fc7b6bf9c3eb742acf1743a1cb4d7b (HEAD -> main, origin/main, origin/HEAD)
Author: fluxcdbot <fluxcdbot@particule.io>
Date:   Thu Feb 4 09:27:40 2021 +0000

    update image

diff --git a/clusters/fluxcd-demo/fullapp.yaml b/clusters/fluxcd-demo/fullapp.yaml
index 636eda1..b1b224d 100644
--- a/clusters/fluxcd-demo/fullapp.yaml
+++ b/clusters/fluxcd-demo/fullapp.yaml
@@ -1,4 +1,3 @@
----
 apiVersion: apps/v1
 kind: Deployment
 metadata:
@@ -16,10 +15,10 @@ spec:
         app: helloworld
     spec:
       containers:
-        image: particule/helloworld # {"$imagepolicy": "flux-system:helloworld"}
+        image: particule/helloworld:1.1.0 # {"$imagepolicy": "flux-system:helloworld"}
```


Et pour finir, on va valider qu'une nouvelle image en `2.0.0` n'update pas
notre Deployment.

```console
$ docker push particule/helloworld:2.0.0
```

## Conclusion

Alors oui, c'est exactement comme avant. Sauf qu'on est heureux d'annoncer que
la fonctionnalité est de nouveau disponible avec les nouvelles CRD associées.
Peut-être n'aviez vous pas mis à jour Flux vers Flux v2 justement parce que
cette fonctionnalité était absente ? N'hésitez pas à nous en parler sur notre
[Twitter](https://twitter.com/particuleio) !

Gitops apporte énormément de sérénité et de rigueur à vos déploiements, n'hésitez
pas [à nous contacter](mailto:romain@particule.io) si vous souhaitez mettre en
place ces mécanismes dans votre organisation.


L'équipe [Particule](https://particule.io)
