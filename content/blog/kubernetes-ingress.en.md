---
Title: Ingress Controller with Træfɪk and Let's Encrypt
lang: en
Date: 2016-10-04
Category: Kubernetes
Series:  Kubernetes deep dive
Summary: Kubernetes offers the Ingress feature, which abstract the configuration of a load balancer for services. Coupled with Træfɪk, a cloud reverse proxy, it is possible to add on the fly HTTPS encryption with Let's Encrypt.
Author: Kevin Lefevre
image: images/thumbnails/kubernetes.png
---

<center><img src="/images/docker/kubernetes.png" alt="Kubernetes" width="400" align="middle"></center>

Still with the alpha/beta features but not that much (it's been here since v1.1), this week we'll focus on the *Ingress* resource that makes publishing services a lot easier. First we'll see what *Ingress* and *Ingress Controller* are then we'll demo with an awesome cloud native reverse proxy that implements the Ingress feature. To stay swag, we'll throw in automatic and on the fly Let's Encrypt certificates generation, because it tastes better when it is free.

Before we start you can check out [Romain's article](http://blog.osones.com/traefik-un-reverse-proxy-pour-vos-conteneurs.html) (for the moment it's only available in French) which describe what Træfɪk is, and how it works with Docker.

### Kubernetes Object

#### Ingress Resource

An *ingress* is a relativly simple object that define a set of applicative routes. Those rules will allow the configuration of a reverse proxy in front of Kubernetes services.

Without *ingress*, Kubernetes services are directly exposed :

```bash
    internet
        |
  ------------
  [ Services ]
```

*Ingress* happens between the Internet and Kubernetes services :

```bash
    internet
        |
   [ Ingress ]
   --|-----|--
   [ Services ]
```

How do we define *ingress* rules :

```yaml
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

In the above example, we define virtual hosts, which are each routed to different backend. Each backend must have a Kubernetes service defined to ensure TCP/UDP load balancing to the correct set of PODs via *kube-proxy*.

Ok so we have a YAML file, with a bunch of rules, but how do we use them ?

To do so we have to use an *Ingress Controller*, it is not directly into Kubernetes but rely on external components that implements the [*ingress controller* specs](https://github.com/kubernetes/contrib/tree/master/ingress/controllers)

#### Ingress Controller

Alone, ingress definitions don't do much. To be applied, they need an *ingress controller* : a reverse proxy that's plugged into Kubernetes API, watches for creation/update/deletion of *ingress* rules, and configures itself accordingly.

A controller does the following :

- Poll Kubernetes API
- Apply configuration base on template
- Reload service

Google offers its own controller on GCE/GKE but there are others available based on multiples OSS that evolve to support Kubernetes :

- [Nginx](https://github.com/kubernetes/contrib/tree/master/ingress/controllers)
- [HA Proxy](https://github.com/kubernetes/contrib/tree/master/ingress/controllers)
- [Træfɪk](https://docs.traefik.io/toml/#kubernetes-ingress-backend)
- Probably others

### Let's Træfɪk and Let's Encrypt

What is [Træfɪk](https://traefik.io/) ?

> Træfɪk is a reverse proxy and load-balancer designed for micro services (e.g. Containers). It is very simple, written in Go, and supports a lot backend types : Consul, Etcd, Docker, Kubernetes, Mesos, etc. It can also be backed by a classic static configuration file and a mix of the above to act as a classic reverse proxy.

In addition, Træfɪk supports the [ACME](https://github.com/ietf-wg-acme/acme/) protocol used by [Let's Encrypt](https://letsencrypt.org/). We are able to publish services and to support TLS automaticly and for free (and that's Cloud (automaticly, not free) !

#### Træfɪk configuration for Kubernetes

First, we need to deploy the *ingress controller* with a *Deployment* :

```yaml
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


We'are using experimental Træfɪk image because it includes the latest commits for Kubernetes and also for the HTTP Auth basic and digest that have not yet been merged into stable. To store Let's Encrypt certificates, we need to use a volume otherwise they will be regenerated every time the pod reboots. Let's encrypt has a 20 certificates per week rate limit so be careful :)

I'm using an *HostPath* for the demo but you can use whatever volume type suits your configuration.

The container is supposed to listen to 80 and 443 via the `hostPort` directive, which is pretty much the same as doing a `docker -p 80:80 -p 443:443` but without NAT. If you are using Kubernetes with [CNI](https://github.com/containernetworking/cni) as a [network plugin](http://kubernetes.io/docs/admin/network-plugins/), the `hostPort` directive is ignored and the container does not use the host network. A workaround is to use a `NodePort` or `ExternalIP` service.

I don't know what you think about but it is a neat solution compare to using `HostPort`, especially in a cluster when you can use multiple Træfɪk instances and a Cloud Load Balancer (e.g on AWS).

Optional, a service in front of Træfɪk :

```yaml
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

In my scenario, I have got only one node so I'm using an `externalIP`, all traffic to port 80 and 443 will be redirected to Træfɪk pod.

Still optional, it is possible to define a service to make Træfɪk webui accessible (it will be accessible from the outside and also published via Traefik and an *ingress* rule) :

```yaml
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

Finally and the most important, we define a *configmap* containing Træfɪk configuration :

```yaml
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

We define entrypoints : `http` and `https` and a redirection between from `http` to `https` via `[entryPoints.http.redirect]`. It's possible to add authentication via `[entryPoints.https.auth.basic]`. For the moment, it is inly possible at the entrypoint level and not on a per backend basis.

Then for Let's Encrypt configuration :

- `email = "lefevre.kevin@gmail.com"` : username
- `storageFile = "/acme/acme.json"` : certificates storage file (it is also possible to use a KV store to share certificates between Træfɪk instances)
- `entryPoint = "https"` : entrypoint whre ACME is enabled
- `onDemand = true` : enable on the fly generation
- `onHostRule = true` : enable generation based on backend discovery
- `caServer = "https://acme-staging.api.letsencrypt.org/directory"` : uses staging api, to go to production, comment or remove this line
- `[[acme.domains]]`
- `main = "archifleks.net"` : Authorized domain

Domain validation is done via DNS, it's important to have a record pointing to the Træfɪk node or to the load-balancer in front of the service (via cloud provider). In my case, I have a record `* IN A A.B.C.D` for `archifleks.net`.


Once all these files are ready, it's possible to merge them all in a single YAML or to pass each of them to Kubernetes. The files used for this article are available on [Github](https://github.com/ArchiFleKs/containers/tree/master/kubernetes/seedbox)

Full `traefik.yml` file :

```yaml
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

#### Demo

On the cluster, we got the following pods :

```bash
kubectl get pods
NAME                           READY     STATUS    RESTARTS   AGE
couchpotato-1954888086-ehrc3   1/1       Running   1          21d
h5ai-3742736394-idw66          1/1       Running   1          16d
plex-3026742140-9lifq          1/1       Running   1          2d
rtorrent-3337740403-un4rr      1/1       Running   1          10d
sickrage-3769118260-h5c78      1/1       Running   7          21d
```

First we deploy the [`traefik.yml`](https://raw.githubusercontent.com/ArchiFleKs/containers/master/kubernetes/zero.vsense.fr/traefik.yml) previously created :

```bash
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

Træfɪk startup logs :

```bash
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

Communication with Let's Encrypt servers is OK but no certificate is generated, only a user. We can check the `acme.json` file to be sure :

```json
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

For now, Træfɪk is not serving any backend, to do so we must define *ingress* rules with [`ingress.yml`](https://raw.githubusercontent.com/ArchiFleKs/containers/master/kubernetes/zero.vsense.fr/ingress.yml) :

```bash
kubectl create -f ingress.yml
ingress "seedbox" configured
ingress "traefik" configured
ingress "kubernetes-dashboard" configured
```

Træfɪk logs:

```bash
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

We can see 2 things :
- Backends are created on *ingress* rules detection
- Certificates generation is done after backend addition to the pool

Connectivity check :

```bash
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

Ok, for the demo I had to use insecure mode because of the staging API, truth be told, I messed up with volumes the first time and reach the rate limit so I could not generate any more certificates :)

### Conclusion

*Ingress* feature really does simplify application depoyment on Kubernetes. It adds another abstraction layer on top of a complex feature, especially in the container world, where time to live is very low and reverse proxies have to be dynamic.

There are few *ingress controller* for now, Google is pushing its but it is only available on GCE. Another community maintained is the Nginx but it does not natively support Kubernetes and/or Let's Encrypt where Træfɪk does.

Even if very few options are available in Træfɪk, there is a strong community and features are coming up quickly. Træfɪk already supports multiple backends such as Kubernetes, Mesos, Consul but also Let's Encrypt as we saw.

About Kubernetes, the project is becoming more and more pluggable, with a high abstraction level, and rapidly evolving. For exemple with *FlexVolume* and *Dynamic Provisioning*, which allow custom storage solutions to interface with kubernetes without touching core Kubernetes code. It is the same thing with *ingress* controller where (in addition to OSS solution) allow editor to publish software comatible with Kubernetes and the *ingress* feature.

**Kevin Lefevre - [@ArchiFleKs](https://twitter.com/ArchiFleKs)**
