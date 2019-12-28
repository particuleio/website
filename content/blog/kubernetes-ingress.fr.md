---
Title: Ingress Controller avec Træfɪk et Let's Encrypt
Date: 2016-10-04
Category: Kubernetes
Series:  Kubernetes deep dive
Summary: Kubernetes propose la fonctionnalité d'Ingress qui joue le rôle d'un load balancer pour les services. Couplée à Træfɪk, un reverseproxy cloud, il est possible d'ajouter une sécurité HTTPS à la volée via Let's Encrypt.
Author: Kevin Lefevre
image: images/thumbnails/kubernetes.png
lang: fr
---

<center><img src="/images/docker/kubernetes.png" alt="Kubernetes" width="400" align="middle"></center>

Toujours dans les features alpha/beta mais pas trop quand même (depuis la v1.1), nous nous intéressons cette semaine à la notion d'*Ingress* qui va permettre de publier des services plus simplement. Dans cet article nous allons voir dans un premier temps les composants *Ingress Resource* et *Ingress Controller* puis pour la pratique nous allons tester avec [Træfɪk](https://traefik.io/) un reverse proxy qui implémente *Ingress*. Histoire de rester bien swag nous ajouterons la génération de certificats Let's Encrypt à la volée pour les backends parce que le cryptement c'est encore plus cool quand c'est automatique et gratuit.

Avant de démarrer, vous pouvez faire un petit tour sur [l'article de Romain](http://blog.osones.com/traefik-un-reverse-proxy-pour-vos-conteneurs.html) qui présente Træfɪk un peu plus en détail et son fonctionnement avec [Consul](https://www.consul.io/) et Docker.

<br />

# Quels composants?

## Ingress Resource

Un [*ingress*](http://kubernetes.io/docs/user-guide/ingress) est un objet Kubernetes relativement simple qui définit des règles de routage applicatives. Ces règles vont permettre de configurer un reverse proxy en frontal des services.

Sans Ingress, les services Kubernetes sont directement exposés sur Internet :

```
    internet
        |
  ------------
  [ Services ]
```

L'Ingress se positionne au niveau applicatif entre Internet et les services :

```
    internet
        |
   [ Ingress ]
   --|-----|--
   [ Services ]
```

Définition d'un *Ingress* :

```
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: bobox
  annotations:
    kubernetes.io/ingress.class: "traefik"
spec:
  rules:
    - host: seedbox.archifleks.net
      http:
        paths:
          - backend:
              serviceName: h5ai
              servicePort: 80
    - host: tv.archifleks.net
      http:
        paths:
          - backend:
              serviceName: sickrage
              servicePort: 8081
    - host: torrents.archifleks.net
      http:
        paths:
          - backend:
              serviceName: rtorrent-internal
              servicePort: 80
    - host: movies.archifleks.net
      http:
        paths:
          - backend:
              serviceName: couchpotato
              servicePort: 5050

```

Dans l'exemple ci-dessus, on utilise des noms d'hôte virtuels, qui sont ensuite routés chacun vers un backend diffèrent. Chaque backend doit disposer d'un service Kubernetes qui assure le load balancing TCP/UDP vers les PODs via *kube-proxy*.

Nous avons des règles de routage dans un fichier YAML, ok c'est top, mais comment ces règles sont t-elles implémentées ?

Non pas directement par Kubernetes mais par des composant externes qui implémentent la spécification d'[*Ingress Controller*](https://github.com/kubernetes/contrib/tree/master/ingress/controllers).

## Ingress Controller

Seules, les définitions d'Ingress ne font rien de particulier. Pour fonctionner elles ont besoin d'un *Ingress Controller* : un reverse proxy capable de communiquer avec les API Kubernetes, c'est à dire de regarder les *creation/update/deletion* d'Ingress et implémenter les règles définies.

Un contrôleur effectue les tâches suivantes :

- Poll l'API Kubernetes pour vérifier les nouveaux *Ingress*
- Applique la configuration (grâce à des templates)
- Reload le service

Google propose son propre *Ingress Controller* sur GCE, mais il en existe d'autres disponibles sur de multiples plate-formes. En général ce sont des solutions Open Source qui évoluent afin de supporter Kubernetes. On distingue :

- [Nginx](https://github.com/kubernetes/contrib/tree/master/ingress/controllers)
- [HA Proxy](https://github.com/kubernetes/contrib/tree/master/ingress/controllers)
- [Træfɪk](https://docs.traefik.io/toml/#kubernetes-ingress-backend)
- Sûrement d'autres dont je n'ai pas encore entendu parler

# Let's Træfɪk et Let's Encrypt

Qu'est ce que [Træfɪk](https://traefik.io/) ?

Pour citer Romain :

> Træfɪk est un reverse-proxy et un loadbalancer fait pour déployer principalement des microservices (ie conteneurs). Il est nativement simple puisque sa configuration propre est extrêmement limitée étant donné que celle ci est majoritairement "déléguée" à ses backends. Et parmis ces backends, on compte Docker, Consul, k8s, mesos, etcd etc. Personne ne manque à l'appel. Traefik peut même être backé par de simples fichiers statiques et se comporter comme un reverse-proxy classique.

En plus de tout cela, Træfɪk supporte le protocole [ACME](https://github.com/ietf-wg-acme/acme/) utilisé par [Let's Encrypt](https://letsencrypt.org/). On va donc pouvoir publier des services et supporter l'HTTPS automatiquement et gratuitement. Et ça c'est cloud (automatiquement, pas gratuit) !

## Configuration de Træfɪk et des composants Kubernetes

Dans un premier temps, il faut déployer l'*Ingress Controller*. Pour cela on utilise un *Deployment* :

```
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: traefik-ingress-controller
  labels:
    k8s-app: traefik-ingress-lb
spec:
  replicas: 1
  revisionHistoryLimit: 0
  template:
    metadata:
      labels:
        k8s-app: traefik-ingress-lb
        name: traefik-ingress-lb
    spec:
      terminationGracePeriodSeconds: 60
      volumes:
        - name: config
          configMap:
            name: traefik-conf
        - name: acme
          hostPath:
            path: /srv/configs/acme.json
      containers:
        - image: containous/traefik:experimental
          name: traefik-ingress-lb
          imagePullPolicy: Always
          volumeMounts:
            - mountPath: "/config"
              name: "config"
            - mountPath: "/acme/acme.json"
              name: "acme"
          ports:
            - containerPort: 80
              hostPort: 80
            - containerPort: 443
              hostPort: 443
            - containerPort: 8080
          args:
            - --configfile=/config/traefik.toml
            - --web
            - --kubernetes
            - --logLevel=DEBUG
```

L'image Træfɪk expérimental est utilisée car elle contient les derniers commits, notamment pour Kubernetes mais aussi pour l'authentification HTTP Digest et Basic. Afin de stocker les certificats Let's Encrypt, il faut utiliser un volume sinon les certificats sont régénérés à chaque redémarrage du POD et on atteint rapidement le rate limit de 20 certificats par semaine et par domaine. Ici, j'utilise un HostPath par rapport a ma configuration mais n'importe quel type de volume fera l'affaire suivant votre configuration.

Le conteneur est supposé utiliser les ports 443 et 80 de l'hôte, via la directive `hostPort`, qui est équivalent a un `docker -p 443:443 -p 80:80`. Suivant le déploiement de Kubernetes, notamment ceux utilisant [CNI](https://github.com/containernetworking/cni) comme [network plugin](http://kubernetes.io/docs/admin/network-plugins/) cette directive est ignorée et le port n'est pas mappé sur l'hôte. La solution est d'utiliser un service de type `NodePort` ou `ExternalIP` pour palier à ce problème.

Je ne sais pas ce que vous en pensez mais c'est même plutôt élégant surtout dans le cas d'un Cluster ou l'on peut utiliser plusieurs Træfɪk avec un Load Balancer, sur AWS par exemple.

Facultatif, un service devant Træfɪk :

```
---
apiVersion: v1
kind: Service
metadata:
  name: traefik
  labels:
    k8s-app: traefik-ingress-lb
spec:
  selector:
    k8s-app: traefik-ingress-lb
  ports:
    - port: 80
      name: http
    - port: 443
      name: https
  externalIPs:
    - 178.32.28.59
```

Dans mon cas, avec un seul nœud, j'utilise une *ExternalIP*, le trafic à destination des port 80 et 443 sera routé vers le POD Træfɪk.

Toujours facultatif, il est possible de définir un service pour rendre la webui de Træfɪk accessible (qui sera elle même accessible depuis l'extérieur via Traefik et une règle Ingress :

```
---
apiVersion: v1
kind: Service
metadata:
  name: traefik-console
  labels:
    k8s-app: traefik-ingress-lb
spec:
  selector:
    k8s-app: traefik-ingress-lb
  ports:
    - port: 8080
      name: webui
```

Enfin et le plus important, il faut définir *configmap* qui contiendra la configuration de Træfɪk.

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: traefik-conf
data:
  traefik.toml: |
    # traefik.toml
    defaultEntryPoints = ["http","https"]
    [entryPoints]
      [entryPoints.http]
      address = ":80"
      [entryPoints.http.redirect]
      entryPoint = "https"
      [entryPoints.https.auth.basic]
      users = ["klefevre:$apr1$k2qslCn6$0OgA8vhnyC8nJ99YfJMOM/"]
      [entryPoints.https]
      address = ":443"
      [entryPoints.https.tls]
    [acme]
    email = "lefevre.kevin@gmail.com"
    storageFile = "/acme/acme.json"
    entryPoint = "https"
    onDemand = true
    onHostRule = true
    caServer = "https://acme-staging.api.letsencrypt.org/directory"
    [[acme.domains]]
    main = "archifleks.net"
```

Dans un premier temps on définit les entrypoints : http et https, une redirection de http vers https via `[entryPoints.http.redirect]` il est possible de rajouter une authentification via la directive `[entryPoints.https.auth.basic]`. Pour le moment, l'authentification et sur l'entrypoint, il n'est pas possible de spécifié une authentification par backend.

Ensuite pour la configuration Let's Encrypt :

- `email = "lefevre.kevin@gmail.com"` : nom d'utilisateur
- `storageFile = "/acme/acme.json"` : fichier de stockage des certificats
- `entryPoint = "https"` : entrypoint sur lequel on utiliser ACME
- `onDemand = true` : génération des certificats a la demande
- `onHostRule = true` : pré-génération des certificats en fonction des règles de backend
- `caServer = "https://acme-staging.api.letsencrypt.org/directory"` : utilisation de l'API de staging, sans rate limit, pour passer en production, il faut commenter cette ligne
- `[[acme.domains]]`
- `main = "archifleks.net"` : Domaine autorisé pour Let's Encrypt

La validation de domaine se fait via DNS, il est important d'avoir un enregistrement DNS pointant vers le nœud Træfɪk ou vers le load-balancer en frontal du service (suivant le cloud provider). Dans le cas de cet article, avec un seul nœud, l'enregistrement est `*  IN  A   A.B.C.D` pour le domaine `archifleks.net`.

Une fois que l'on a tous ces fichier, il est possible de les concaténer dans un seul fichier YAML ou de les passer séparément à Kubernetes. Les fichiers utilisés pour l'article sont disponibles sur [github](https://github.com/ArchiFleKs/containers/tree/master/kubernetes/zero.vsense.fr)

Le fichier `traefik.yml` complet :

```
---
apiVersion: v1
kind: Service
metadata:
  name: traefik
  labels:
    k8s-app: traefik-ingress-lb
spec:
  selector:
    k8s-app: traefik-ingress-lb
  ports:
    - port: 80
      name: http
    - port: 443
      name: https
  externalIPs:
    - 178.32.28.59
---
apiVersion: v1
kind: Service
metadata:
  name: traefik-console
  labels:
    k8s-app: traefik-ingress-lb
spec:
  selector:
    k8s-app: traefik-ingress-lb
  ports:
    - port: 8080
      name: webui
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: traefik-conf
data:
  traefik.toml: |
    # traefik.toml
    defaultEntryPoints = ["http","https"]
    [entryPoints]
      [entryPoints.http]
      address = ":80"
      [entryPoints.http.redirect]
      entryPoint = "https"
      [entryPoints.http.auth.basic]
      users = ["klefevre:$apr1$k2qslCn6$0OgA8vhnyC8nJ99YfJMOM/"]
      [entryPoints.https.auth.basic]
      users = ["klefevre:$apr1$k2qslCn6$0OgA8vhnyC8nJ99YfJMOM/"]
      [entryPoints.https]
      address = ":443"
      [entryPoints.https.tls]
    [acme]
    email = "lefevre.kevin@gmail.com"
    storageFile = "/acme/acme.json"
    entryPoint = "https"
    onDemand = true
    onHostRule = true
    caServer = "https://acme-staging.api.letsencrypt.org/directory"
    [[acme.domains]]
    main = "archifleks.net"
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: traefik-ingress-controller
  labels:
    k8s-app: traefik-ingress-lb
spec:
  replicas: 1
  revisionHistoryLimit: 0
  template:
    metadata:
      labels:
        k8s-app: traefik-ingress-lb
        name: traefik-ingress-lb
    spec:
      terminationGracePeriodSeconds: 60
      volumes:
        - name: config
          configMap:
            name: traefik-conf
        - name: acme
          hostPath:
            path: /srv/configs/acme/acme.json
      containers:
        - image: containous/traefik:experimental
          name: traefik-ingress-lb
          imagePullPolicy: Always
          volumeMounts:
            - mountPath: "/config"
              name: "config"
            - mountPath: "/acme/acme.json"
              name: "acme"
          ports:
            - containerPort: 80
              hostPort: 80
            - containerPort: 443
              hostPort: 443
            - containerPort: 8080
          args:
            - --configfile=/config/traefik.toml
            - --web
            - --kubernetes
            - --logLevel=DEBUG
```

## Demo

Sur le cluster, on dispose des PODs suivant :

```
kubectl get pods
NAME                           READY     STATUS    RESTARTS   AGE
couchpotato-1954888086-ehrc3   1/1       Running   1          21d
h5ai-3742736394-idw66          1/1       Running   1          16d
plex-3026742140-9lifq          1/1       Running   1          2d
rtorrent-3337740403-un4rr      1/1       Running   1          10d
sickrage-3769118260-h5c78      1/1       Running   7          21d
```

Dans un premier temps, on déploie le fichier [`traefik.yml`](https://raw.githubusercontent.com/ArchiFleKs/containers/master/kubernetes/zero.vsense.fr/traefik.yml) créé dans la partie précédente :

```
kubectl create -f traefik.yml
service "traefik" created
service "traefik-console" created
configmap "traefik-conf" created
deployment "traefik-ingress-controller" created

kubectl get pods
NAME                                         READY     STATUS    RESTARTS   AGE
couchpotato-1954888086-ehrc3                 1/1       Running   1          21d
h5ai-3742736394-idw66                        1/1       Running   1          16d
plex-3026742140-9lifq                        1/1       Running   1          2d
rtorrent-3337740403-un4rr                    1/1       Running   1          10d
sickrage-3769118260-h5c78                    1/1       Running   7          21d
traefik-ingress-controller-379161919-3lhff   1/1       Running   0          51s
```

Logs du démarrage de Træfɪk :

```
time="2016-09-29T13:54:54Z" level=info msg="Preparing server https &{Network: Address::443 TLS:0xc42030ac00 Redirect:<nil> Auth:0xc4203f6df0}"
time="2016-09-29T13:54:54Z" level=debug msg="Generating default certificate..."
time="2016-09-29T13:54:55Z" level=info msg="Generating ACME Account..."
time="2016-09-29T13:54:58Z" level=info msg="Retrieving ACME certificates..."
time="2016-09-29T13:54:58Z" level=debug msg="Loading ACME certificates [archifleks.net]..."
time="2016-09-29T13:54:58Z" level=info msg="Preparing server http &{Network: Address::80 TLS:<nil> Redirect:0xc4203d2e70 Auth:0xc4203f6da0}"
time="2016-09-29T13:54:58Z" level=debug msg="Kubernetes CA cert: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
time="2016-09-29T13:54:58Z" level=debug msg="Using environment provided kubernetes endpoint"
time="2016-09-29T13:54:58Z" level=debug msg="Kubernetes endpoint: https://10.3.0.1:443"
time="2016-09-29T13:54:58Z" level=debug msg="Using label selector: ''"
time="2016-09-29T13:54:58Z" level=debug msg="Configuration received from provider kubernetes: {}"
time="2016-09-29T13:54:58Z" level=debug msg="Last kubernetes config received more than 2s, OK"
time="2016-09-29T13:55:00Z" level=info msg="Retrieved ACME certificates"
time="2016-09-29T13:55:00Z" level=debug msg="Testing certificate renew..."
```

La communication avec Let's Encrypt est OK mais aucun certificat n'as été généré, uniquement un compte utilisateur. Il est possible de le vérifier sur le volume de l'hôte :

```
cat acme.json
{
  "Email": "lefevre.kevin@gmail.com",
  "Registration": {
    "body": {
      "resource": "reg",
      "id": 359553,
      "key": {
      },
      "contact": [
        "mailto:lefevre.kevin@gmail.com"
      ],
      "agreement": "https://letsencrypt.org/documents/LE-SA-v1.1.1-August-1-2016.pdf"
    },
    "uri": "https://acme-staging.api.letsencrypt.org/acme/reg/359553",
    "new_authzr_uri": "https://acme-staging.api.letsencrypt.org/acme/new-authz",
    "terms_of_service": "https://letsencrypt.org/documents/LE-SA-v1.1.1-August-1-2016.pdf"
  },
  "DomainsCertificate": {
    "Certs": []
  }

```

Pour le moment, Træfɪk ne sert aucun backend, il faut pour cela définir une Ingress Resource comme vu précédemment.

Le fichier [`ingress.yml`](https://raw.githubusercontent.com/ArchiFleKs/containers/master/kubernetes/zero.vsense.fr/ingress.yml) :

```
kubectl create -f ingress.yml
ingress "seedbox" configured
ingress "traefik" configured
ingress "kubernetes-dashboard" configured
```

Logs de Træfɪk :

```
time="2016-09-29T14:05:51Z" level=debug msg="Waited for kubernetes config, OK"
time="2016-09-29T14:05:51Z" level=debug msg="Creating frontend kubernetes.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Wiring frontend kubernetes.archifleks.net to entryPoint http"
time="2016-09-29T14:05:51Z" level=debug msg="Creating route kubernetes.archifleks.net Host:kubernetes.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Creating entryPoint redirect http -> https : ^(?:https?:\\/\\/)?([\\da-z\\.-]+)(?::\\d+)?(.*)$ -> https://$1:443$2"
time="2016-09-29T14:05:51Z" level=debug msg="Wiring frontend kubernetes.archifleks.net to entryPoint https"
time="2016-09-29T14:05:51Z" level=debug msg="Creating route kubernetes.archifleks.net Host:kubernetes.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Creating backend kubernetes.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Creating load-balancer wrr"
time="2016-09-29T14:05:51Z" level=debug msg="Creating server kubernetes-dashboard-600072875-fb17t at http://10.2.80.4:9090 with weight 1"
time="2016-09-29T14:05:51Z" level=debug msg="Creating frontend movies.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Wiring frontend movies.archifleks.net to entryPoint http"
time="2016-09-29T14:05:51Z" level=debug msg="Creating route movies.archifleks.net Host:movies.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Wiring frontend movies.archifleks.net to entryPoint https"
time="2016-09-29T14:05:51Z" level=debug msg="Creating route movies.archifleks.net Host:movies.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Creating backend movies.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Creating load-balancer wrr"
time="2016-09-29T14:05:51Z" level=debug msg="Creating server couchpotato-1954888086-ehrc3 at http://10.2.80.6:5050 with weight 1"
time="2016-09-29T14:05:51Z" level=debug msg="Creating frontend seedbox.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Wiring frontend seedbox.archifleks.net to entryPoint http"
time="2016-09-29T14:05:51Z" level=debug msg="Creating route seedbox.archifleks.net Host:seedbox.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Wiring frontend seedbox.archifleks.net to entryPoint https"
time="2016-09-29T14:05:51Z" level=debug msg="Creating route seedbox.archifleks.net Host:seedbox.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Creating backend seedbox.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Creating load-balancer wrr"
time="2016-09-29T14:05:51Z" level=debug msg="Creating server h5ai-3742736394-idw66 at http://10.2.80.7:80 with weight 1"
time="2016-09-29T14:05:51Z" level=debug msg="Creating frontend torrents.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Wiring frontend torrents.archifleks.net to entryPoint http"
time="2016-09-29T14:05:51Z" level=debug msg="Creating route torrents.archifleks.net Host:torrents.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Wiring frontend torrents.archifleks.net to entryPoint https"
time="2016-09-29T14:05:51Z" level=debug msg="Creating route torrents.archifleks.net Host:torrents.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Creating backend torrents.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Creating load-balancer wrr"
time="2016-09-29T14:05:51Z" level=debug msg="Creating server rtorrent-3337740403-un4rr at http://10.2.80.3:80 with weight 1"
time="2016-09-29T14:05:51Z" level=debug msg="Creating frontend traefik.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Wiring frontend traefik.archifleks.net to entryPoint http"
time="2016-09-29T14:05:51Z" level=debug msg="Creating route traefik.archifleks.net Host:traefik.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Wiring frontend traefik.archifleks.net to entryPoint https"
time="2016-09-29T14:05:51Z" level=debug msg="Creating route traefik.archifleks.net Host:traefik.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Creating backend traefik.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Creating load-balancer wrr"
time="2016-09-29T14:05:51Z" level=debug msg="Creating server traefik-ingress-controller-379161919-1f3wy at http://10.2.80.32:8080 with weight 1"
time="2016-09-29T14:05:51Z" level=debug msg="Creating frontend tv.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Wiring frontend tv.archifleks.net to entryPoint http"
time="2016-09-29T14:05:51Z" level=debug msg="Creating route tv.archifleks.net Host:tv.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Wiring frontend tv.archifleks.net to entryPoint https"
time="2016-09-29T14:05:51Z" level=debug msg="Creating route tv.archifleks.net Host:tv.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Creating backend tv.archifleks.net"
time="2016-09-29T14:05:51Z" level=debug msg="Creating load-balancer wrr"
time="2016-09-29T14:05:51Z" level=debug msg="Creating server sickrage-3769118260-h5c78 at http://10.2.80.9:8081 with weight 1"
time="2016-09-29T14:05:51Z" level=info msg="Server configuration reloaded on :443"
time="2016-09-29T14:05:51Z" level=info msg="Server configuration reloaded on :80"
time="2016-09-29T14:05:51Z" level=debug msg="Loading ACME certificates [movies.archifleks.net]..."
time="2016-09-29T14:05:51Z" level=debug msg="Loading ACME certificates [traefik.archifleks.net]..."
time="2016-09-29T14:05:51Z" level=debug msg="Loading ACME certificates [tv.archifleks.net]..."
time="2016-09-29T14:05:51Z" level=debug msg="Loading ACME certificates [torrents.archifleks.net]..."
time="2016-09-29T14:05:51Z" level=debug msg="Loading ACME certificates [kubernetes.archifleks.net]..."
time="2016-09-29T14:05:51Z" level=debug msg="Loading ACME certificates [seedbox.archifleks.net]..."
time="2016-09-29T14:05:59Z" level=debug msg="Loaded ACME certificates [movies.archifleks.net]"
time="2016-09-29T14:05:59Z" level=debug msg="Got certificate for domains [movies.archifleks.net]"
time="2016-09-29T14:06:04Z" level=debug msg="Loaded ACME certificates [seedbox.archifleks.net]"
time="2016-09-29T14:06:04Z" level=debug msg="Got certificate for domains [seedbox.archifleks.net]"
time="2016-09-29T14:06:06Z" level=debug msg="Loaded ACME certificates [tv.archifleks.net]"
time="2016-09-29T14:06:06Z" level=debug msg="Got certificate for domains [tv.archifleks.net]"
time="2016-09-29T14:06:09Z" level=debug msg="Loaded ACME certificates [torrents.archifleks.net]"
time="2016-09-29T14:06:09Z" level=debug msg="Got certificate for domains [torrents.archifleks.net]"
time="2016-09-29T14:06:09Z" level=debug msg="Using label selector: ''"
time="2016-09-29T14:06:10Z" level=debug msg="Loaded ACME certificates [seedbox.archifleks.net]"
time="2016-09-29T14:06:10Z" level=debug msg="Got certificate for domains [seedbox.archifleks.net]"
......
```

On remarque 2 choses :
- La création des backends dés que l'Ingress est détectée
- La génération des certificats automatiquement dés que les backends sont ajoutés

On test la connectivité pour valider le tout :

```
http tv.archifleks.net

HTTP/1.1 302 Found
Content-Length: 5
Content-Type: text/plain; charset=utf-8
Date: Thu, 29 Sep 2016 14:17:08 GMT
Location: https://tv.archifleks.net:443/

Found

http --verify=no --auth user:pass https://tv.archifleks.net -v

GET / HTTP/1.1
Accept: */*
Accept-Encoding: gzip, deflate
Authorization: Basic a2xlZmV2cmU6a2xvOTh6c2Q=
Connection: keep-alive
Host: tv.archifleks.net
User-Agent: HTTPie/0.9.4

HTTP/1.1 302 Found
Content-Length: 0
Content-Type: text/html; charset=UTF-8
Date: Thu, 29 Sep 2016 14:22:00 GMT
Location: /login/?next=%2F
Server: TornadoServer/4.2.1
Vary: Accept-Encoding
```

Bon pour la demo je suis obligé de me mettre en insecure parce que j'utilise l'API staging, et surtout que je me suis planté la première fois et que j'ai grillé tout mon quota de la semaine donc je ne peux plus générer de certificats pour le moment :)

# Conclusion

La fonctionnalité d'Ingress simplifie vraiment le déploiement d'applications sur Kubernetes et rajoute une couche d'abstraction à une fonctionnalité parfois complexe à implémenter dans le monde des conteneurs.

Il existe encore peu d'*Ingress Controller*, Google développe le sien mais il est uniquement disponible sur GCE. Un autre contrôleur maintenu par la communauté est le contrôleur Nginx mais Nginx ne supporte pas de manière native Kubernetes ou Let's Encrypts contrairement à Træfɪk.

Même si peu d'options sont disponibles dans Træfɪk, la communauté est forte, et les fonctionnalités se développent rapidement. Træfɪk supporte déjà de multiples backend comme Kubernetes, Mesos, Consul mais aussi Let's Encrypt comme nous venons de le voir.

En ce qui concerne Kubernetes, le projets devient de plus en plus pluggable, avec un haut niveau d'abstraction et qui s'étend à grande vitesse. Par exemple avec les [FlexVolume](http://blog.osones.com/presentation-de-torus-un-systeme-de-fichier-distribue-cloud-natif.html), qui vont permettre a différentes solutions de stockage s'interfacer avec Kubernetes. Également, et c'est l'objet de cet article, les *Ingress Controller* permettent (en plus des solutions Open Source) aux éditeurs d'implémenter cette fonctionnalité et de fournir des produits compatibles avec Kubernetes.

**Kevin Lefevre - [@ArchiFleKs](https://twitter.com/ArchiFleKs)**
