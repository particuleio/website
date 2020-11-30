---
Title: Sécuriser vos applications Kubernetes avec Cert-Manager et Scaleway DNS
Date: 2020-11-24
Category: Kubernetes
Summary: Utiliser Cert-Manager et Scaleway DNS pour générer des certificats TLS et sécuriser vos applications sur Kubernetes Kapsule
Author: Romain Guichard
image: images/thumbnails/logo-scaleway-elements.png
imgSocialNetwork: images/og/kapsule-certmanager.png
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

[Dans un dernier article, nous vous faisions découvrir (ou pas) le service
External-DNS](https://particule.io/blog/scaleway-externaldns/) permettant de
synchroniser l'état de nos `Services` et `Ingress` avec
un service DNS. Suite à la sortie du DNS as a Service chez Scaleway,
External-DNS devenait compatible avec ce dernier et s'intégrait parfaitement
avec Kubernetes Kapsule.


Grâce à External-DNS, nous sommes capables de déployer une application
quasiment de bout en bout, celle ci est déployée en haute disponibilité avec
notre couple `Deployment`/`Service` et est exposée via un nom de domaine avec le
couple Ingress/External-DNS.

Mais il manque quelque chose : **la sécurisation de votre application avec
TLS.**

## Cert-Manager

[Cert-Manager](https://cert-manager.io/) est un gestionnaire natif de
certificats pour Kubernetes. Il
permet la génération de certificats depuis différentes sources comme Let's
Encrypt, HashiCorp Vault ou bien un auto-signé. Le contrôleur de cert-manager
se chargera de renouveller le certificat afin d'éviter son expiration.

Afin de ne pas permettre à n'importe qui de demander un certificat pour
n'importe quel CommonName, cert-manager utilise le protocole ACME afin
d'effectuer un challenge permettant de prouver votre identité. Deux grands
mécanismes existent pour valider votre possession du nom de domaine pour lequel
vous désirez obtenir un certificat valide : HTTP-01 et DNS-01.

<https://letsencrypt.org/fr/docs/challenge-types/>

Long story short, le challenge HTTP-01 vous demande de prouver être capable
d'héberger du contenu à l'endroit où pointe votre nom de domaine et le
challenge DNS-01 vous demande de prouver que vous posséder le nom de domaine en
y créant un enregistrement DNS.

HTTP-01 marche à peu près partout, il n'y a pas de dépendance à un tiers (à
moins que votre fournisseur bloque le port 80, mais qui fait ça ?). DNS-01
demande de posséder un service DNS piloté par une API afin de créer les
enregistrements qui permettront de réussir le challenge. Et ça tombe bien,
Scaleway a ça et depuis peu propose
[un webhook](https://github.com/scaleway/cert-manager-webhook-scaleway)
 pour Kubernetes permettant d'utiliser
leur service DNS avec cert-manager.

Voici donc la pièce manquante du puzzle pour déployer, réellement de bout en
bout, notre application.

## Pré-requis

- un cluster Kubernetes Kapsule
- [Helm v3](https://helm.sh/docs/intro/install/) sur votre PC
- un DNS configuré sur Kapsule (nous utiliserons `scw.particule.cloud` ici)

Pour l'installation de Kapsule vous pouvez vous reporter à [notre première
article](https://particule.io/blog/scaleway-kapsule/).

## Installation de cert-manager

Là c'est la partie facile. Il suffit d'appliquer le yaml officiel.

```console
$ kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.0.4/cert-manager.yaml
```

Attendez quelques instants que les CRD cert-manager soient correctement
installées avant de passer à la suite.

## Installation du webhook Scaleway

```console
$ git clone https://github.com/scaleway/cert-manager-webhook-scaleway.git
$ cd cert-manager-webhook-scaleway
$ helm install scaleway-webhook deploy/scaleway-webhook
```

L'étape suivante est de créer un `Issuer`, il s'agit du composant qui va faire la
demande de certificat à Let's Encrypt. Afin de permettre à l`Issuer` de valider
le challenge DNS, il va lui falloir un accès au DNS de Scaleway et donc un
accès à vos crédentials. Stockons les dans un Secret :

Votre `Secret`, l'`Issuer` et le webhook doivent être placés dans le même
namespace.

```yaml
---
apiVersion: v1
stringData:
  SCW_ACCESS_KEY: <YOUR-SCALEWAY-ACCESS-KEY>
  SCW_SECRET_KEY: <YOUR-SCALEWAY-SECRET-KEY>
kind: Secret
metadata:
  name: scaleway-secret
type: Opaque
```

Grâce au paramètre `stringData`, vous n'avez pas besoin d'encoder vos données
en base64.

On crée maintenant l'`Issuer`.

```yaml
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: scaleway
spec:
  acme:
    email: romain@particule.io
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    # for production use this URL instead
    # server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: scaleway-acme-secret
    solvers:
    - dns01:
        webhook:
          groupName: acme.scaleway.com
          solverName: scaleway
          config:
            accessKeySecretRef:
              key: SCW_ACCESS_KEY
              name: scaleway-secret
            secretKeySecretRef:
              key: SCW_SECRET_KEY
              name: scaleway-secret
```

Nous sommes maintenant prêt à demander un certificat à Let's Encrypt.

## Application de test

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: helloworld
spec:
  replicas: 1
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
        ports:
        - name: web
          containerPort: 80
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
  type: ClusterIP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: helloworld
  annotations:
    cert-manager.io/issuer: scaleway
    kubernetes.io/tls-acme: "true"
spec:
  rules:
    - host: helloworld.scw.particule.cloud
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: helloworld
                port:
                  number: 80
  tls:
  - hosts:
    - helloworld.scw.particule.cloud
    secretName: helloworld.scw.particule.cloud-cert
```

Le `Deployment` et le `Service` sont très classiques, rien à signaler de ce
coté.

En revanche l'`Ingress` a subit quelques ajouts. Premièrement, il utilise
`networking.k8s.io/v1` et la syntaxe de `spec.rules` change légèrement. Mais
surtout nous avons des changements au niveau des annotations et au niveau de la
`spec.tls`.

Deux annotations sont ajoutées, la première défini l'issuer que nous allons
utiliser, la deuxième active le protocole ACME.

Au niveau du TLS, on défini le `Secret` dans lequel sera stocké le certificat
pour notre `Ingress`.

On applique et on va surveiller la création de notre certificat :

```console
$ kubectl get certificates -w
```

La création prend un peu de temps (~2min), n'hésitez pas à regarder les events de votre
cluster pour voir les erreurs arivées ^^

```console
$ kubectl get events
```

Vous devriez à un moment obtenir votre certificat.

```console
$ kubectl get events
0s          Normal    Issuing             certificate/helloworld.scw.particule.cloud-cert                             The certificate has been successfully issued

$ kubectl get certs
NAME                                  READY   SECRET                                AGE
helloworld.scw.particule.cloud-cert   True    helloworld.scw.particule.cloud-cert   8m
```

Et on peut effectivement voir notre certificat :

```console
$ curl https://helloworld.scw.particule.cloud -vvvv -k
*   Trying 212.47.236.1:443...
* TCP_NODELAY set
* Connected to helloworld.scw.particule.cloud (212.47.236.1) port 443 (#0)
[...]
* Server certificate:
*  subject: CN=helloworld.scw.particule.cloud
*  start date: Nov 21 16:31:19 2020 GMT
*  expire date: Feb 19 16:31:19 2021 GMT
*  issuer: CN=Fake LE Intermediate X1
*  SSL certificate verify result: unable to get local issuer certificate (20), continuing anyway.
* Using HTTP2, server supports multi-use
* Connection state changed (HTTP/2 confirmed)
* Copying HTTP/2 data in stream buffer to connection buffer after upgrade: len=0
* Using Stream ID: 1 (easy handle 0x5621f56a1e40)
> GET / HTTP/2
> Host: helloworld.scw.particule.cloud
> user-agent: curl/7.68.0
> accept: */*
[...]
> strict-transport-security: max-age=15724800; includeSubDomains

<html>
<head>
```

## ClusterIssuer

Comme nous avons utilisé un `Issuer` dans le namespace default, seuls les
`Ingress` de ce namespace pourront demander un certificat. Afin de permettre ce
mécanisme à l'ensemble du cluster, nous allons utiliser un `ClusterIssuer`. Il
s'agit de la même ressource mais cluster-wide (comme la différence entre un
`Role` et un `ClusterRole`).

Afin que cela puisse fonctionner, nous allons devoir modifier plusieurs choses.
Tout comme l'`Issuer`, le `ClusterIssuer` va définir le webhook à utiliser pour
résoudre le challenge DNS ainsi que les crédentials nécessaires.
Dans notre exemple précédent l'`Issuer` référençait un `Secret` dans son
propre namespace mais dans le cas d'un `ClusterIssuer` celui ci le référence
dans le namespace de cert-manager. Si on souhaite que le webhook puisse
effectivement récupérer ce secret, nous avons deux choix :

- installer le webhook et le `Secret` dans le namespace cert-manager
- installer le webhook dans un namespace dédié, le `Secret` dans le namespace
de cert-manager et modifier les RBAC du helm chart afin que le webhook ait accès aux
`Secrets` du namespace cert-manager

Question de simplicité, nous allons utiliser la première solution ^^

La ressource `Issuer` et `ClusterIssuer` est identique en tous points, vous
n'avez qu'à modifier le Kind et le tour est joué. Pour le webhook et le
`Secret` vous n'avez qu'à spécifier `-n cert-manager` au déploiement.

À part ça rien ne change mais vous obtiendrez un comportement "multi-tenant" où
plusieurs namespaces pourront utiliser l'issuer sans configuration et sans
avoir accès aux crédentials Scaleway.

## External-DNS

Pour compléter tout ceci, nous pouvons activer External-DNS afin que
le nom de domaine pour lequel nous avons crée notre certificat possède bien un
enregistrement.

Vous pouvez reprendre
[notre précédent article](https://particule.io/blog/scaleway-externaldns/)
sur le sujet.

Ou alors, vous pouvez utiliser [le module
Terraform](https://github.com/particuleio/terraform-kubernetes-addons/tree/main/modules/scaleway)
 écrit par Particule vous
permettant de déployer External-DNS très simplement. Il vous suffit d'ajouter
ce code :

```terraform
module "addons" {
  source = "particuleio/addons/kubernetes//modules/scaleway"
  version = "~> 1.0"
  external-dns = {
    enabled = true
    scw_access_key = <YOUR-SCALEWAY-ACCESS-KEY
    scw_secret_key = <YOUR-SCALEWAY-SECRET-KEY
    scw_default_organization_id = <YOUR-SCALEWAY-ORGANIZATION-ID>
  }
}
```

Nous reviendrons bientôt sur ce module Terraform et sur le travail que nous
effectuons pour rendre le déploiement de Kubernetes Kapsule encore plus efficace
et simple.

## Conclusion

Un gros merci aux équipes de Scaleway pour avoir développé ce webhook, une
nouvelle corde à l'arc de Kubernetes Kapsule lui permettant de rivaliser avec
d'autres offres Kubernetes managées.


[**Romain Guichard**](https://www.linkedin.com/in/romainguichard), CEO &
co-founder

