---
Title: Utiliser External-DNS avec Kubernetes Kapsule de Scaleway
Date: 2020-09-10
Category: Kubernetes
Summary: External-DNS permet d'automatiquement créer des enregistrements DNS pour vos Services et Ingress déployés sur Kubernetes. On vous explique comment mettre ceci en place avec Kubernetes Kapsule de Scaleway
Author: Romain Guichard
image: images/thumbnails/logo-scaleway-elements.png
imgSocialNetwork: images/og/kapsule-externaldns.png
lang: fr
---

Kubernetes Kapsule est le service de Kubernetes managé de Scaleway. Nous avons
déjà traité la présentation du service dans un
[précédent article](https://particule.io/blog/scaleway-kapsule/). Nous avions
été assez élogieux, mettant particulièrement en avant le travail effectué sur
le provider Terraform permettant de déployer et de manager, entièrement en
infrastructure as code, nos clusters Kubernetes.

Nous avons aussi abordé l'utilisation des PodSecurityPolicy sur Kapsule, nous
vous laissons [(re)découvrir cet article si vous le
souhaitez](https://particule.io/blog/scaleway-psp/).

Quelle est notre problématique ici ?

Au sein de Kubernetes, le système DNS interne (assuré par CoreDNS par défaut)
assure en permanence la création, modification et suppression d'enregistrements
DNS pour les pods et les Services. Ainsi tous vos Services se voient attribuer
un nom dns de la forme : `mon-service.mon-namespace.svc.cluster.local`,
pointant sur la ClusterIP du Service. Pareil pour les pods, ceux ci ont un
enregistrement DNS de la forme
`adresse-ip-du-pod.mon-namespace.pod.cluster.local`. Moins utile vu qu'il faut
connaître l'IP du pod alors qu'il s'agit de l'information justement recherchée
au moyen du DNS.

Quoi qu'il en soit, l'utilisation du DNS pour les Services est omniprésente et
il s'agit du moyen que vous devriez utiliser pour faire communiquer vos
applications à l'intérieur de Kubernetes.

En interne cela fonctionne bien. Le problème apparait quand ces Services sont
exposés à l'extérieur du cluster notamment avec le type `LoadBalancer` qui va
générer des IP publiques. Kubernetes n'a, nativement, aucun moyen de faire
matcher votre application masuperapp.particule.io avec l'IP publique générée
par votre Service de type `LoadBalancer`. Et c'est ce que External-DNS résout.

### External-DNS

External-DNS est un addon à Kubernetes extrêmement populaire permettant de
synchroniser les Services et Ingress exposés avec un provider DNS.
Contrairement à CoreDNS, le composant DNS interne de Kubernetes, External-DNS
n'est pas un serveur DNS, il ne fait
qu'enregistrer les informations récupérées depuis l'API Server vers un provider
DNS. External-DNS permet donc de dynamiquement configurer vos enregistrements DNS
en vous concentrant uniquement sur Kubernetes.

Et ce qui nous intéressant ici c'est [le provider **Scaleway** disponible pour
External-DNS](https://github.com/kubernetes-sigs/external-dns/pull/1643).

![scaleway](https://upload.wikimedia.org/wikipedia/fr/thumb/b/b0/Scaleway_logo_2018.svg/langfr-560px-Scaleway_logo_2018.svg.png)

### Déploiement d'un cluster Kubernetes Kapsule

Commençons par se servir du provider Terraform pour déployer un cluster
Kubernetes Kapsule. [Nous avons déjà abordé ce sujet dans un précédent article,
vous pouvez vous y reporter pour plus d'infos](https://particule.io/blog/scaleway-kapsule/).

Voici le code utilisé :

```
provider "scaleway" {
  zone            = "fr-par-1"
  region          = "fr-par"
  version         = "~> 1.11"
}

resource "scaleway_k8s_cluster_beta" "k8s" {
  name = "particule"
  version = "1.19.0"
  cni = "weave"
  enable_dashboard = false
  ingress = "nginx"
}

resource "scaleway_k8s_pool_beta" "commonpool" {
  cluster_id = scaleway_k8s_cluster_beta.k8s.id
  name = "commonpool"
  node_type = "GP1-XS"
  size = 1
  autoscaling = true
  autohealing = true
  min_size = 1
  max_size = 5
}
```

On applique et quelques instants plus tard :

```
$ terraform apply

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

[...]

Plan: 4 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

scaleway_registry_namespace_beta.main: Creating...
scaleway_k8s_cluster_beta.k8s: Creating...
scaleway_registry_namespace_beta.main: Creation complete after 1s [id=fr-par/b6d93ffb-908e-4955-b192-e4f42f0a9be6]
scaleway_k8s_cluster_beta.k8s: Creation complete after 7s [id=fr-par/5e1a8c9b-7430-46bd-a24c-9eed4edf9490]
scaleway_k8s_pool_beta.commonpool: Creating...
local_file.kubeconfig: Creating...
local_file.kubeconfig: Creation complete after 0s [id=b1eb17dc3631477154ee08878f6e197578c9c439]
scaleway_k8s_pool_beta.commonpool: Still creating... [10s elapsed]
scaleway_k8s_pool_beta.commonpool: Still creating... [20s elapsed]
scaleway_k8s_pool_beta.commonpool: Still creating... [30s elapsed]
scaleway_k8s_pool_beta.commonpool: Creation complete after 37s [id=fr-par/c2ab627a-1f99-477c-bf29-bcab15576479]

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:

cluster_url = https://5e1a8c9b-7430-46bd-a24c-9eed4edf9490.api.k8s.fr-par.scw.cloud:6443

$ kubectl --kubeconfig kubeconfig get node
NAME                                             STATUS   ROLES    AGE   VERSION
scw-particule-commonpool-b0b52be520ed4d8bbc170   Ready    <none>   16m   v1.19.0
```

Notre cluster est prêt.


Le DNS as a Service de Scaleway est sorti en juin 2020 mais est toujours en
Beta.

[![scw-dns](/images/externaldns/scw-dns.jpg)](https://twitter.com/Scaleway/status/1275044780330770432)

Peu importe, les fonctions de base de l'API sont fonctionnelles
n'avons qu'à y configurer un domaine.

Vous allez devoir valider la possession de ce domaine en renseignant un
enregistrement TXT là où est géré actuellement votre domaine. Cela dépendra de
chacun d'entre vous. Une
fois la validation effectuée (celle ci est quasi instantannée) votre domaine
sera activé chez Scaleway et il faudra faire
pointer les NS de votre domaine vers ceux de Scaleway pour qu'une résolution
complète fonctionne.

- ns0.dom.scw.cloud.
- ns1.dom.scw.cloud.

![dns](/images/externaldns/dns.png)


### Déploiement de External-DNS


Comme la totalité des addons à Kubernetes, celui ci se déploie dans Kubernetes,
ici sous forme d'un Deployment.

Le support de Scaleway par External-DNS est extrêmement récent (quelques
semaines) et aucune release n'existe actuellement. Nous allons donc devoir
builder notre propre image d'External-DNS depuis la branch master.

```
$ git clone https://github.com/kubernetes-sigs/external-dns
$ cd external-dns
$ make build.docker
```
Vous devriez récupérer une image
`us.gcr.io/k8s-artifacts-prod/external-dns/external-dns:v0.7.3-106-g0947994d`.
Je vais retag cette image et la pousser sur Docker Hub pour que mon
cluster Kubernetes puisse facilement y accéder.

```
$ docker tag us.gcr.io/k8s-artifacts-prod/external-dns/external-dns:v0.7.3-106-g0947994d particule/external-dns:scaleway
$ docker push particule/external-dns:scaleway
```

C'est donc cette dernière image que nous utiliserons pour notre déploiement.
Afin que External-DNS puisse synchroniser notre DNS avec nos Services et nos
ingress, il faut lui donner les droits correspondants. Nous créeons donc un
ServiceAccount pour porter ces droits et nous le donnons à notre pod
external-dns. Pour une question de simplicitié je ne vais surveiller que les
Services avec `--source=service`.

```
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-dns
rules:
- apiGroups: [""]
  resources: ["services","endpoints","pods"]
  verbs: ["get","watch","list"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get","watch","list"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["list","watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-dns-viewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
- kind: ServiceAccount
  name: external-dns
  namespace: default
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
spec:
  replicas: 1
  kselector:
    matchLabels:
      app: external-dns
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      serviceAccountName: external-dns
      containers:
      - name: external-dns
        image: particule/external-dns:scaleway
        args:
        - --source=service
        - --domain-filter=particule.cloud
        - --provider=scaleway
        env:
        - name: SCW_ACCESS_KEY
          value: "<your access key>"
        - name: SCW_SECRET_KEY
          value: "<your secret key>"
        - name: SCW_DEFAULT_ORGANIZATION_ID
          value: "<your organization ID>"
```

On applique :

```
$ kubectl get pod
NAME                            READY   STATUS    RESTARTS   AGE
external-dns-68fc6d9854-l9xqf   1/1     Running   0          10s
```

Il ne nous reste plus qu'à déployer une application pour tester.

```
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: helloworld
  labels:
    app: helloworld
spec:
  replicas: 3
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
---
apiVersion: v1
kind: Service
metadata:
  name: helloworld
  annotations:
    external-dns.alpha.kubernetes.io/hostname: helloworld.particule.cloud
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 80
  selector:
    app: helloworld
  type: LoadBalancer
```

External-DNS devrait donc associer l'IP du LoadBalancer qui sera crée au nom
`helloworld.particule.cloud`.

On applique et on regarde les logs d'External-DNS :

```
$ kubectl apply -f helloworld-externaldns.yml
deployment.apps/helloworld configured
service/helloworld configured


$ kubectl logs external-dns-68fc6d9854-l9xqf
[...]
time="2020-09-10T14:19:26Z" level=info msg="Skipping record particule.cloud because type NS is not supported"
time="2020-09-10T14:19:26Z" level=info msg="Skipping record particule.cloud because type NS is not supported"
time="2020-09-10T14:19:26Z" level=info msg="Updating zone particule.cloud"
time="2020-09-10T14:19:26Z" level=info msg="Adding record" data=195.154.70.34 priority=0 record=helloworld.particule.cloud ttl=300 type=A
time="2020-09-10T14:19:26Z" level=info msg="Adding record" data="\"heritage=external-dns,external-dns/owner=default,external-dns/resource=service/default/helloworld\"" priority=0 record=helloworld.particule.cloud ttl=300 type=TXT
```

On voit que deux enregistrements ont été crée et le premier, celui qui nous
intéresse, contient bien l'IP de notre LoadBalancer :

```
$ kubectl get svc
NAME         TYPE           CLUSTER-IP    EXTERNAL-IP     PORT(S)        AGE
helloworld   LoadBalancer   10.36.30.30   195.154.70.34   80:30350/TCP   23m
```

Si on interroge les serveurs DNS de Scaleway, on voit que l'enregistrement
est bien présent :

```
$ dig @ns0.dom.scw.cloud. helloworld.particule.cloud +short
195.154.70.34
```

![webpage](/images/externaldns/webpage.png)


### Conclusion

External-DNS fait parti de nos addons préférés. Associé à la quasi totalité des
cloud provider, celui ci fait des miracles avec très peu de choses à faire au
préalable. L'effet obtenu est généralement extrêmement apprécié puisqu'il
permet avec un simple `kubectl apply` de déployer une application accessible
via un nom de domaine sans aucune autre intervention manuelle. Couplez ça à
Let's Encrypt et vous avez votre application accessible publiquement, via un
nom de domaine et via un canal sécurisé avec TLS.

Il est d'ailleurs aussi possible d'utiliser External-DNS en dehors d'un cloud
provider, [Kevin Lefevre](https://linkedin.com/in/kevinlefevre) en parle dans
un de [nos autres articles](https://particule.io/en/blog/k8s-no-cloud/).


[**Romain Guichard**](https://www.linkedin.com/in/romainguichard), CEO &
co-founder

