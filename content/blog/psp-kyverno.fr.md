---
Title: "Gérer ses Policies sur Kubernetes avec Kyverno"
Date: 2021-02-24
Category: Kubernetes
Summary: Les PSP sont en voie de disparition, regardons comment automatiser l'application des best practices Kubernetes grâce à Kyverno
Author: Theo "Bob" Massard
image: images/thumbnails/kyverno.png
imgSocialNetwork: images/og/kubefed-eks.png
lang: fr
---

Déjà mentionné dans [notre article][article-psp-deprecated] qui annonçait la dépréciation des PodSecurityPolicies et leur
suppression à partir de la version 1.25, [Kyverno][kyverno-home] s'annonce être un digne successeur à 
ces dernières.

Pour rappel, les PSP permettaient aux administrateurs de cluster de forcer l'application de bonnes pratiques
en définissant un ensemble de règles qui étaient exécutées lors de la phase d'admission, au moyen
d'un Admission Controller _compiled-in_.

Par exemple, les policies peuvent servir à:
- Forcer la mise en place de labels afin d'harmoniser la gestion de vos ressources
- Restreindre la surface d'attaque en interdisant de monter des `hostPath`
- Empêcher un Pod d'utiliser des `hostPort`
- Mettre en place des valeurs par défaut pour les limitations de ressource

Dans cet article, nous verrons comment mettre en place Kyverno, découvrir ses fonctionnalités
et explorer ce que nous offre cette méthode de gestion des Policies.

### Qu'est-ce que Kyverno ?

Kyverno est un _moteur de gestion de Policies_, permettant de définir des règles en tant que ressources Kubernetes.
Une fois installé, Kyverno va analyser chaque ressource et appliquer les règles correspondantes.

Site: <https://kyverno.io/>

Afin d'avoir un comportement similaire, Kyverno intervient de la même façon que les PSP mais au moyen
d'un Admission Controller dynamique qui traite des callbacks (webhooks d'admissions)
de validation et de mutation en provenance de l'apiserver Kubernetes.

Les `Policies` Kyverno sont découpées en 3 parties:
- Les règles, ayant chacune un selecteur et une action
- Le selecteur de ressource de la règle, en inclusion ou en exclusion,
- L'action de la règle, qui peut être une validation, une mutation ou une génération de ressource

_Référence: [Kyverno - Policy Structure](https://kyverno.io/docs/writing-policies/structure/)._

Elles peuvent être appliquées au niveau d'un Namespace (`Policy`) ou du Cluster (`ClusterPolicy`).
Ces deux ressources génèrent des `PolicyReports` (ou des `ClusterPolicyReports`) se basant sur le
schéma proposé dans la [Kubernetes Policy WG][kube-policy-wg].

### Mise en place de Kyverno

#### Installation

Commençons par mettre en place un environnement pour explorer les possibilités de Kyverno!
En utilisant **kind** (présenté sur [notre blog][article-kube-local] !), configurons un cluster local:

```console
$ kind create cluster --name kyverno
Creating cluster "kyverno" ...
 ✓ Ensuring node image (kindest/node:v1.20.2) 🖼
 ✓ Preparing nodes 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-kyverno"
You can now use your cluster with:

kubectl cluster-info --context kind-kyverno

Thanks for using kind! 😊
```

Il existe différentes méthodes d'installation pour mettre en place Kyverno, utilisons le
Chart Helm officiel pour bootstrapper notre cluster.

```console
$ helm repo add kyverno https://kyverno.github.io/kyverno/
$ helm repo update
$ helm install kyverno kyverno/kyverno --namespace kyverno --create-namespace
NAME: kyverno
LAST DEPLOYED: Wed Feb 24 11:10:31 2021
NAMESPACE: kyverno
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
Thank you for installing kyverno 😀

Your release is named kyverno.

We have installed the "default" profile of Pod Security Standards and set them in audit mode.

Visit https://kyverno.io/policies/ to find more sample policies.
```

Après quelques secondes, nous avons un cluster configuré avec un profile de sécurité par défaut en mode *audit*
implémentant des règles basées sur les [Pod Security Standards][kube-pss].


#### Bootstrapping

Nous pouvons lister les CRDs installés par le chart Helm:
```
$ kubectl api-resources --api-group kyverno.io
NAME                          SHORTNAMES   APIVERSION            NAMESPACED   KIND
clusterpolicies               cpol         kyverno.io/v1         false        ClusterPolicy
clusterreportchangerequests   crcr         kyverno.io/v1alpha1   false        ClusterReportChangeRequest
generaterequests              gr           kyverno.io/v1         true         GenerateRequest
policies                      pol          kyverno.io/v1         true         Policy
reportchangerequests          rcr          kyverno.io/v1alpha1   true         ReportChangeRequest
$ kubectl api-resources --api-group wgpolicyk8s.io
NAME                   SHORTNAMES   APIVERSION                NAMESPACED   KIND
clusterpolicyreports   cpolr        wgpolicyk8s.io/v1alpha1   false        ClusterPolicyReport
policyreports          polr         wgpolicyk8s.io/v1alpha1   true         PolicyReport
```

Les règles du profile "default" sont définies via des `ClusterPolicies`:
```
$ kubectl get cpol -n kyverno
NAME                             BACKGROUND   ACTION
disallow-add-capabilities        true         audit
disallow-host-namespaces         true         audit
disallow-host-path               true         audit
disallow-host-ports              true         audit
disallow-privileged-containers   true         audit
disallow-selinux                 true         audit
require-default-proc-mount       true         audit
restrict-apparmor-profiles       true         audit
restrict-sysctls                 true         audit
```

En effet, nous avons déjà un bon nombre de `Policies` ! Cependant, pas d'inquiétude.
Nous pouvons observer qu'elles ont toutes été définies avec `background=true` et `action=audit`.
Cette configuration indique à Kyverno que ces règles ne doivent pas être bloquantes.
Toutes les 15 minutes, une analyse est lancée pour chaque règle sur les ressources
présentes à cet instant au sein du Cluster et génèrent des ClusterPolicyReports.

### Exemples d'utilisation

#### Création d'une ClusterPolicy

Il est temps de mettre en place notre première `Policy` ! 
Définissons une règle simple qui vérifie la présence d'un label identifiant
le nom de l'application à laquelle un `Pod` correspond.

```yaml
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
spec:
  validationFailureAction: enforce
  rules:
    - name: check-for-label-name
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "label `app.kubernetes.io/name` is required"
        pattern:
          metadata:
            labels:
              app.kubernetes.io/name: "?*"
```

La règle `check-for-label-name` permet de considérer comme prérequis le label
`app.kubernetes.io/name` pour le déploiement des ressources de type `Pod`.

Pour résumer cette règle:

_Il est obligatoire pour tout `Pod` d'avoir un label `app.kubernetes.io/name` d'une longueur supérieure ou égale à 1 caractère._

Après avoir appliqué notre `ClusterPolicy`, nous obtenons la ressource suivante:

```yaml
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
  annotations:
    pod-policies.kyverno.io/autogen-controllers: DaemonSet,Deployment,Job,StatefulSet,CronJob
spec:
  background: true
  rules:
    - match:
      resources:
        kinds:
          - Pod
      name: check-for-label-name
      validate:
        message: label `app.kubernetes.io/name` is required
      pattern:
        metadata:
          labels:
            app.kubernetes.io/name: ?*
    - match:
      resources:
        kinds:
          - DaemonSet
          - Deployment
          - Job
          - StatefulSet
      name: autogen-check-for-label-name
      validate:
        message: label `app.kubernetes.io/name` is required
        pattern:
          spec:
            template:
              metadata:
                labels:
                  app.kubernetes.io/name: ?*
    - match:
      resources:
        kinds:
          - CronJob
      name: autogen-cronjob-check-for-label-name
      validate:
        message: label `app.kubernetes.io/name` is required
        pattern:
          spec:
            jobTemplate:
              spec:
                template:
                  metadata:
                    labels:
                      app.kubernetes.io/name: ?*
      validationFailureAction: enforce
```

On retrouve notre règle "check-for-label-name", mais deux autres règles ont été autogénérées
afin d'appliquer le comportement que nous souhaitons aux autres ressources permettant
de définir des pods.

Ces règles sont créées par les `autogen-controllers` ([link][kyverno-autogen]) référencés par
l'annotation correspondante qui sert d'annotation par défaut. Définir manuellement cette annotation permet de
modifier le comportement de génération automatique de règles.

Essayons de déployer une ressource qui enfreint la règle que nous venons de créer:
```
$ kubectl run sample --image=busybox 
Error from server: admission webhook "validate.kyverno.svc" denied the request: 

resource Pod/default/sample was blocked due to the following policies

require-labels:
  check-for-labels: 'validation error: label `app.kubernetes.io/name` is required. Rule check-for-label-name failed at path /metadata/labels/app.kubernetes.io/name/'
$ kubectl run sample --image=busybox  --labels app.kubernetes.io/name=valid
pod/sample created
```

Notre `Policy` a une `validationFailureAction=enforce`, il nous est donc impossible de créer une
ressource ne validant pas l'intégralité des règles définies!

Après avoir ajouté un label pour le nom de notre `Pod`, le webhook d'admission Kyverno
valide la requête et la ressource est créée.

#### Le mode "audit"

Lors du déploiement du Chart Helm, un profil par défaut a été configuré en mode audit.

_We have installed the "default" profile of Pod Security Standards and set them in audit mode._

Ce mode de validation de `Policy` est _non-intrusif_ et permet de mettre progressivement
en application les règles. Il n'empêche pas la création des ressources qui ne sont pas conformes 
à la `Policy` mais va historiser les infractions dans des `PolicyReport` (`polr`) si la
ressource est _namespaced_ (comme un `Deployment` ou un `ConfigMap`) dans le namespace de la ressource, 
ou des `ClusterPolicyReports` (`cpolr`) s'il s'agit de ressource non _namespaced_ (un `Namespace`)

Lors de la création d'un `Deployment`, le template du `Pod` enfreint une `ClusterPolicy`.
L'infraction sera reportée dans une `PolicyReport` dans le namespace du `Pod`.

Lors de la création d'une `IngressClass`, l'absence de label enfreint une autre `ClusterPolicy`.
L'infraction sera reportée dans une `ClusterPolicyReport`.

Comme mentionné précédemment, le mode audit va périodiquement (toutes les 15 minutes)
analyser les ressources et générer des reports.

Configurons une `Policy` en mode audit ainsi qu'un `Pod` de test:

```yaml
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-tier-on-pod
spec:
  validationFailureAction: audit
  background: true
  rules:
    - name: check-for-tier-on-pod
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "if set, label `app.kubernetes.io/tier` must be any of ['frontend', 'backend', 'internal']"
        pattern:
          metadata:
            labels:
              =(app.kubernetes.io/tier): "frontend | backend | internal"
---
apiVersion: v1
kind: Pod
metadata:
  labels:
    app.kubernetes.io/tier: uknown
    app.kubernetes.io/name: example-pod
  name: bad-tier
spec:
  containers:
    - image: nginx:latest
      name: example-tier
```
_Si le label `app.kubernetes.io/tier` existe, il doit correspondre à l'une des valeurs frontend, backend ou internal._

Après quelques instants, nous pouvons observer un avertissement venant de l'admission-controller:
```
$ kubectl describe pod bad-tier  | grep -A 5 Events
Events:
  Type     Reason           Age   From                  Message
  ----     ------           ----  ----                  -------
  Warning  PolicyViolation  8s   admission-controller  Rule(s) 'check-for-tier-on-pod' of policy 'require-tier-on-pod' failed to apply on the resource
  Normal   Scheduled        8s   default-scheduler     Successfully assigned default/bad-tier to kyverno-control-plane
  Normal   Pulling          7s   kubelet               Pulling image "nginx:latest"
$ kubectl get polr
NAME              PASS   FAIL   WARN   ERROR   SKIP   AGE
polr-ns-default   1      1      0      0       0      30m
```

Nous pouvons obtenir un _report_ complet en effectuant un _describe_ sur le `PolicyReport`
du `Namespace` correspondant.

```yaml
---
apiVersion: wgpolicyk8s.io/v1alpha1
kind: PolicyReport
metadata:
  name: polr-ns-default
  namespace: default
results:
  - message: 'validation error: if set, label `app.kubernetes.io/tier` must be any of
    [''frontend'', ''backend'', ''internal'']. Rule check-for-tier-on-pod failed at
    path /metadata/labels/app.kubernetes.io/tier/'
    policy: require-tier-on-pod
    resources:
      - apiVersion: v1
        kind: Pod
        name: bad-tier
        namespace: default
        uid: 6e743322-5b2a-4ad7-bc79-eca437ab82db
    rule: check-for-tier-on-pod
    scored: true
    status: fail
  - category: Pod Security Standards (Default)
    message: validation rule 'host-namespaces' passed.
    policy: disallow-host-namespaces
    resources:
      - apiVersion: v1
        kind: Pod
        name: sample
        namespace: default
        uid: 19dc0c5b-3960-4178-8bb0-6cd61a23c089
    rule: host-namespaces
    scored: true
    status: pass
summary:
  error: 0
  fail: 1
  pass: 1
  skip: 0
  warn: 0
```

Les `PolicyReports` permettent d'avoir une vue d'ensemble des infractions
locales au namespace dans lequel elles résident.

Chaque report inclut un récapitulatif de l'application des règles avec le nombre
d'infraction, de validation, d'avertissements, ...

### Comment implémenter Kyverno

#### Lors de la mise en place d'un Cluster

Afin de partir sur de bonnes bases, vous pouvez intégrer Kyverno à votre Cluster Kubernetes
après sa création en surchargeant [les valeurs par défaut][kyverno-chart-values] du Chart Helm.

Une version plus sécurisée du profile "[default][kyverno-psp-default]" est disponible via
le profile "[restricted][kyverno-psp-restricted]" et peut être accompagnée d'un
`validationFailureAction=enforce` afin de garantir l'intégrité et la sécurité du cluster.

#### Dans un Cluster existant

Il est totalement possible d'ajouter Kyverno à une configuration en utilisant le même procédé.
Attention cependant à ne pas enforce les Policies que vous mettez en place de façon à
ne pas cause d'interruption.

Une transition vers des ressources conformes aux règles que vous souhaitez définir pourrait s'effectuer de
en utilisant la méthode suivante:
- Définition des règles à implémenter via Kyverno en mode audit
- Observer les infractions via les PolicyReports et les ClusterPolicyReports
- Ajout d'une étape de validation dans les CI/CD via [Kyverno CLI][kyverno-cli]
- Passage en mode "enforce" lorsque les ressources sont conformes à la Policy

### Conclusion

La mise en place d'une solution de gestion de Policy est une étape importante
concernant la sécurisation des clusters Kubernetes.

Kyverno réussit à répondre à cette problématique d'une manière élégante et peut se révéler
être un excellent remplaçant aux PSP. La dimension _Kubernetes Native_ rend la courbe
d'apprentissage très douce, ne nécessitant pas d'apprendre de nouvelle syntaxe.

Dans cet article, nous avons couvert les similarités au niveau des PSP. Cependant,
Kyverno propose des fonctionnalités additionnelles, telle que la [mutation][kyverno-policies-mutate]
de ressources permettant de rajouter des valeurs par défauts, ou encore la [génération][kyverno-policies-validate]
de ressources qui offre la possibilité de répliquer des ressources à travers différents namespaces
ou d'automatiser certaines opérations.

[**Theo "Bob" Massard**](https://www.linkedin.com/in/tbobm/), Cloud Native Engineer

[article-kube-local]: https://particule.io/blog/kubernetes-local/
[article-psp-deprecated]: https://particule.io/blog/kubernetes-psp-deprecated/
[kube-policy-wg]: https://github.com/kubernetes-sigs/wg-policy-prototypes/tree/master/policy-report
[kube-pss]: https://kubernetes.io/docs/concepts/security/pod-security-standards/
[kyverno-autogen]: https://kyverno.io/docs/writing-policies/autogen/
[kyverno-chart-values]: https://github.com/kyverno/kyverno/blob/main/charts/kyverno/values.yaml
[kyverno-cli]: https://kyverno.io/docs/kyverno-cli/
[kyverno-home]: https://kyverno.io/
[kyverno-policies-mutate]: https://kyverno.io/docs/writing-policies/mutate/
[kyverno-policies-validate]: https://kyverno.io/docs/writing-policies/validate/
[kyverno-psp-default]: https://kyverno.io/policies/pod-security/default/
[kyverno-psp-restricted]: https://kyverno.io/policies/pod-security/restricted/
