---
Title: Dynamic DNS and LoadBalancing without cloud provider
Date: 2020-05-14
Category: Kubernetes
Summary: How to provide DNS and Load Balancer integration without Cloud Provider on Kubernetes
Author: Kevin Lefevre
image: images/thumbnails/kubernetes.png
lang: en
---

We often talk about managed Kubernetes or running Kubernetes in the Cloud but we
also run Kubernetes on less "cloudy" environment, like VMware or bare metal
server.

You may also hear a lot about how awesome the cloud provider integrations are:
you can get password less credentials to access managed services, provision
cloud load balancer without manual intervention, create DNS entries
automatically etc.

These integration are often not available when running on premises except if you
are using a well supported Cloud provider like
[OpenStack](https://github.com/kubernetes/cloud-provider-openstack). So how can
you get the automation benefits of Cloud Native environment when running on bare
metal or VMs ?

So what do we want we most, let's go feature by feature.

All the manifests use throughout this article are available
[here](https://github.com/clusterfrak-dynamics/gitops-template)

### Gitops

As usual we are using [Gitops](https://www.weave.works/technologies/gitops/)
with [FluxCD](https://fluxcd.io) to deploy our resources into our cluster,
whether they are on a cloud provider or on premises. You can check out our
[articles about Flux](https://particule.io/en/blog/weave-flux-cncf-incubation/)
[here]() and [there]().

To get started you can use our [gitops
template](https://github.com/clusterfrak-dynamics/gitops-template/) and
customize it to your needs. You can also deploy directly the manifests with
`kubectl` if this is more suitable.

Let's dive into our components.

### Load Balancing

When running on a Cloud provider you often get a Load Balancer out of the box.
When running on bare metal or VMs, your load balancers stay in `pending` state.

So first we'd like for our service type `LoadBalancer` to not
stay in `pending` and to be able to provision dynamic load balancer if needed
without having to configure an `haproxy` or other manually.

Enters [`metallb`](https://metallb.universe.tf/configuration/) which can provide
virtual load balancer in two modes:

* [BGP](https://metallb.universe.tf/configuration/#bgp-configuration)
* [ARP](https://metallb.universe.tf/configuration/#layer-2-configuration)

The latter is simpler because it works on almost any layer 2 network without
further configuration.

In ARP mode, metal lb is quite simple to configure. You just have to give it a
bunch of IP it can use and you are good to go.

The manifests are available
[here](https://github.com/clusterfrak-dynamics/gitops-template/blob/master/flux/resources/metallb-system/metallb.yaml)
or [in the official
documentation](https://metallb.universe.tf/installation/#installation-by-manifest).
To configure the IP address needed, this is done [with a
*ConfigMap*](https://metallb.universe.tf/configuration/).

[`metallb-config.yaml`](https://github.com/clusterfrak-dynamics/gitops-template/blob/master/flux/resources/metallb-system/metallb-config.yaml):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 10.10.39.200-10.10.39.220
```

You also need to generate a secret to secure metallb components communication,
you can use [this
script](https://github.com/clusterfrak-dynamics/gitops-template/blob/master/flux/resources/metallb-system/generate-secret.sh)
to generate the Kubernetes secret yaml:

```bash
kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)" -o yaml --dry-run=client > metallb-secret.yaml
```

Once everything is deployed you should see your pods inside the `metallb-system`
namespace:

```bash
NAME                          READY   STATUS    RESTARTS   AGE
controller-57f648cb96-tvr9q   1/1     Running   0          2d1h
speaker-7rd8p                 1/1     Running   0          2d1h
speaker-7t7rg                 1/1     Running   0          2d1h
speaker-8qm2t                 1/1     Running   0          2d1h
speaker-bks4s                 1/1     Running   0          2d1h
speaker-cz6bc                 1/1     Running   0          2d1h
speaker-h8b54                 1/1     Running   0          2d1h
speaker-j6bss                 1/1     Running   0          2d1h
speaker-phvv7                 1/1     Running   0          2d1h
speaker-wdwjc                 1/1     Running   0          2d1h
speaker-xj25p                 1/1     Running   0          2d1h
```

We are now ready to test our load balancers. To do so let's move directly to our
next topic.

### Ingress controller

When running on Cloud Provider, in addition of the classic layer 4 load
balancer, you sometime can get a Layer 7 load balancer, on GCP and AWS (with the
application load balancer for example). But these have limited feature and are
not really cost efficient et you often want/need an ingress controller ton
manager your traffic from you Kubernetes cluster.

This ingress controller is often published on the outside with a service type
`LoadBalancer`. That's why our previous metal lb deployment will come in handy.

One of the first and most used ingress controller is the [nginx-ingress
one](https://github.com/kubernetes/ingress-nginx) which can [easily be deployed
with Helm](https://github.com/helm/charts/tree/master/stable/nginx-ingress).

Since we are using Flux with Helm Operator, we are using an [Helm Release
available here] from which you can derived the `values.yaml` if needed to
manually deployed via Helm:

```yaml
apiVersion: helm.fluxcd.io/v1
kind: HelmRelease
metadata:
  name: nginx-ingress
  namespace: nginx-ingress
spec:
  releaseName: nginx-ingress
  chart:
    repository: https://kubernetes-charts.storage.googleapis.com
    version: 1.36.3
    name: nginx-ingress
  values:
    controller:
      publishService:
        enabled: true
      kind: "DaemonSet"
      service:
        enabled: true
        externalTrafficPolicy: Local
      daemonset:
        hostPorts:
          http: 80
          https: 443
    defaultBackend:
      replicaCount: 2
    podSecurityPolicy:
      enabled: true
```

Nothing out of the ordinary, we are using a
[*DaemonSet*](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
and the default is to use a service type `LoadBalancer`.

If we check our newly deployed release:

```bash
k -n nginx-ingress get helmreleases.helm.fluxcd.io
NAME            RELEASE         PHASE       STATUS     MESSAGE                                                                       AGE
nginx-ingress   nginx-ingress   Succeeded   deployed   Release was successful for Helm release 'nginx-ingress' in 'nginx-ingress'.   2d1h

or 

helm -n nginx-ingress ls
NAME            NAMESPACE       REVISION        UPDATED                                 STATUS          CHART                   APP VERSION
nginx-ingress   nginx-ingress   2               2020-05-12 15:06:25.832403094 +0000 UTC deployed        nginx-ingress-1.36.3    0.30.0

k -n nginx-ingress get svc
NAME                            TYPE           CLUSTER-IP       EXTERNAL-IP    PORT(S)                      AGE
nginx-ingress-controller        LoadBalancer   10.108.113.212   10.10.39.200   80:31465/TCP,443:30976/TCP   2d1h
nginx-ingress-default-backend   ClusterIP      10.102.217.148   <none>         80/TCP                       2d1h
```

We can see that our service is of type `LoadBalancer` and that the external IP
is one that we defined inside our previous *ConfigMap* for MetalLB.

Let's create a `demo` namespace and check the behavior when we create an ingress
object:

```bash
kubectl create ns demo
```

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: nginx
  name: nginx
  namespace: demo
spec:
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - image: nginx
        name: nginx
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: nginx
  name: nginx
  namespace: demo
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 80
  selector:
    app: nginx
---
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: nginx
  name: nginx
  namespace: demo
spec:
  rules:
  - host: nginx.test.org
    http:
      paths:
      - backend:
          serviceName: nginx
          servicePort: 80
```

`nginx-ingress` is able to publish the service by default which mean it can
report the load balancer IP address into the ingress object:

```bash
k -n demo get ingress

NAME    CLASS    HOSTS            ADDRESS        PORTS     AGE
nginx   <none>   nginx.test.org   10.10.39.200   80, 443   47h
```

We can see that the LoadBalancer IP address is embedded into the ingress object.
This is one the requirement to be able to use [external DNS](https://github.com/kubernetes-sigs/external-dns) which is our next
topic.


### External DNS

Now that we have both our layer 4 loadbalancer (metallb) which can carry traffic
to our layer 7 load balancer (nginx-ingress) inside our cluster, how can we
manage DNS dynamically ? A commonly use tools to do so is
[`external-dns`](https://github.com/kubernetes-sigs/external-dns) which can keep
in sync Kubernetes *Services* and *Ingress* with a DNS provider.

And this is pretty simple to use, that is if you are running of using one of the
widely use DNS provider ([AWS Route53](https://aws.amazon.com/route53/) or
[Google Cloud DNS](https://cloud.google.com/dns)). External DNS also supports
[other
providers](https://github.com/kubernetes-sigs/external-dns#status-of-providers)
but if you are not using one of the directly supported provider, you are in no
luck.

Let's say for example your on premises DNS are managed by Active Directory, you
are kind of stuck because there is no way external DNS is going to writing
directly into your Active Directory DNS.

So how can we get this dynamic DNS feature ? Sure you can use a wildcard DNS
record and direct it to our `nginx-ingress` loadbalancer IP, that's one way to
do it. This works if you are only using one LoadBalancer as an entry point for
your cluster but if you want to use other protocol than HTTP or other service of
type loadbalancer, you would still need to update manually some DNS records.

The other solution is to delegate a DNS zone for your Cluster.

External DNS supports CoreDNS as a backend, so we can delegate a DNS zone from
our active directory to our CoreDNS server running inside Kubernetes.

#### Caveats

It sounds quite simple but when diving into the [external-dns / CoreDNS part](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/coredns.md) we noticed that the only supported backend for CoreDNS that works with External DNS is Etcd. So yes, we need an Etcd cluster :/. You may also notice that the [readme](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/coredns.md) relies on [`etcd-operator`](https://github.com/coreos/etcd-operator) which is now archived and deprecated, and that it also does not encrypt communication with Etcd.

We made an up to date guide to make up for those caveats, first we are going to
use cilium's fork of [`etcd-operator`](https://github.com/cilium/cilium-etcd-operator) that will take care of provisioning a 3 nodes etcd cluster and generate TLS assets.

The manifests are [available here](https://github.com/clusterfrak-dynamics/gitops-template/tree/master/flux/resources/external-dns).


#### Etcd operator

First we apply the etcd [Custom Resource Definition](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/):

```yaml
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: etcdclusters.etcd.database.coreos.com
spec:
  additionalPrinterColumns:
  - JSONPath: .metadata.creationTimestamp
    description: 'CreationTimestamp is a timestamp representing the server time when
      this object was created. It is not guaranteed to be set in happens-before order
      across separate operations. Clients may not set this value. It is represented
      in RFC3339 form and is in UTC. Populated by the system. Read-only. Null for
      lists. More info: https://git.k8s.io/community/contributors/devel/api-conventions.md#metadata'
    name: Age
    type: date
  group: etcd.database.coreos.com
  names:
    kind: EtcdCluster
    listKind: EtcdClusterList
    plural: etcdclusters
    shortNames:
    - etcd
    singular: etcdcluster
  scope: Namespaced
  version: v1beta2
  versions:
  - name: v1beta2
    served: true
    storage: true
```

Then we can deploy the [etcd operator](https://raw.githubusercontent.com/clusterfrak-dynamics/gitops-template/master/flux/resources/external-dns/cilium-etcd-operator.yaml).

Soon after we should end up with etcd pods and secrets:

```bash
k -n external-dns get pods

NAME                                    READY   STATUS    RESTARTS   AGE
cilium-etcd-mnphzk2tjl                  1/1     Running   0          2d1h
cilium-etcd-operator-55d89bbff7-cw8rc   1/1     Running   0          2d1h
cilium-etcd-tsxm5rsckj                  1/1     Running   0          2d1h
cilium-etcd-wtnqt22ssg                  1/1     Running   0          2d1h
etcd-operator-6c57fff6f5-g92pc          1/1     Running   0          2d1h

k -n external-dns get secrets
NAME                                 TYPE                                  DATA   AGE
cilium-etcd-client-tls               Opaque                                3      2d1h
cilium-etcd-operator-token-zmjcl     kubernetes.io/service-account-token   3      2d1h
cilium-etcd-peer-tls                 Opaque                                3      2d1h
cilium-etcd-sa-token-5dhtn           kubernetes.io/service-account-token   3      2d1h
cilium-etcd-secrets                  Opaque                                3      2d1h
cilium-etcd-server-tls               Opaque                                3      2d1h
```

#### CoreDNS

We can then deploy CoreDNS with the [official Helm chart](https://github.com/helm/charts/tree/master/stable/coredns).

Just like before, our resource is an [*HelmRelease*](https://github.com/clusterfrak-dynamics/gitops-template/blob/master/flux/resources/external-dns/coredns.yaml) from which you can derive
the `values.yaml` if needed:

```yaml
apiVersion: helm.fluxcd.io/v1
kind: HelmRelease
metadata:
  name: coredns
  namespace: external-dns
spec:
  releaseName: coredns
  chart:
    repository: https://kubernetes-charts.storage.googleapis.com
    version: 1.10.1
    name: coredns
  values:
    serviceType: "NodePort"
    replicaCount: 2
    serviceAccount:
      create: true
    rbac:
      pspEnable: true
    isClusterService: false
    extraSecrets:
    - name: cilium-etcd-client-tls
      mountPath: /etc/coredns/tls/etcd
    servers:
      - zones:
        - zone: .
        port: 53
        plugins:
        - name: errors
        - name: health
          configBlock: |-
            lameduck 5s
        - name: ready
        - name: prometheus
          parameters: 0.0.0.0:9153
        - name: forward
          parameters: . /etc/resolv.conf
        - name: cache
          parameters: 30
        - name: loop
        - name: reload
        - name: loadbalance
        - name: etcd
          parameters: test.org
          configBlock: |-
            stubzones
            path /skydns
            endpoint https://cilium-etcd-client.external-dns.svc:2379
            tls /etc/coredns/tls/etcd/etcd-client.crt /etc/coredns/tls/etcd/etcd-client.key /etc/coredns/tls/etcd/etcd-client-ca.crt
```

The important lines are the following:

```yaml
extraSecrets:
- name: cilium-etcd-client-tls
  mountPath: /etc/coredns/tls/etcd

and

- name: etcd
  parameters: test.org
  configBlock: |-
    stubzones
    path /skydns
    endpoint https://cilium-etcd-client.external-dns.svc:2379
    tls /etc/coredns/tls/etcd/etcd-client.crt /etc/coredns/tls/etcd/etcd-client.key /etc/coredns/tls/etcd/etcd-client-ca.crt
```

Where we are mounting and using etcd secret to use TLS communication with etcd.

#### External DNS

Finally we can wrap things up and install external DNS. As usual we are going to
use the [official Helm chart](https://github.com/helm/charts/tree/master/stable/external-dns) and an [HelmRelease](https://github.com/clusterfrak-dynamics/gitops-template/blob/master/flux/resources/external-dns/external-dns.yaml):

```yaml
apiVersion: helm.fluxcd.io/v1
kind: HelmRelease
metadata:
  name: external-dns
  namespace: external-dns
spec:
  releaseName: external-dns
  chart:
    repository: https://charts.bitnami.com/bitnami
    version: 2.22.4
    name: external-dns
  values:
    provider: coredns
    policy: sync
    coredns:
      etcdEndpoints: "https://cilium-etcd-client.external-dns.svc:2379"
      etcdTLS:
        enabled: true
        secretName: "cilium-etcd-client-tls"
        caFilename: "etcd-client-ca.crt"
        certFilename: "etcd-client.crt"
        keyFilename: "etcd-client.key"
```

Here, same as before, we are supply the secret name and the path to etcd TLS
assets to secure communication and we are enabling the coredns provider.

So here is our final `external-dns` namespace:

```bash
k -n external-dns get svc
NAME                 TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)                     AGE
cilium-etcd          ClusterIP   None           <none>        2379/TCP,2380/TCP           2d2h
cilium-etcd-client   ClusterIP   10.105.37.25   <none>        2379/TCP                    2d2h
coredns-coredns      NodePort    10.99.62.135   <none>        53:31071/UDP,53:30396/TCP   2d1h
external-dns         ClusterIP   10.103.88.97   <none>        7979/TCP                    2d1h

k -n external-dns get pods
NAME                                    READY   STATUS    RESTARTS   AGE
cilium-etcd-mnphzk2tjl                  1/1     Running   0          2d2h
cilium-etcd-operator-55d89bbff7-cw8rc   1/1     Running   0          2d2h
cilium-etcd-tsxm5rsckj                  1/1     Running   0          2d2h
cilium-etcd-wtnqt22ssg                  1/1     Running   0          2d2h
coredns-coredns-5c86dd5979-866s2        1/1     Running   0          2d
coredns-coredns-5c86dd5979-vq86w        1/1     Running   0          2d
etcd-operator-6c57fff6f5-g92pc          1/1     Running   0          2d2h
external-dns-96d9fbc64-j22pf            1/1     Running   0          2d1h
```

If you look back at our ingress from before:

```yaml
---
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: nginx
  name: nginx
  namespace: demo
spec:
  rules:
  - host: nginx.test.org
    http:
      paths:
      - backend:
          serviceName: nginx
          servicePort: 80
```

```bash
k -n demo get ingress

NAME    CLASS    HOSTS            ADDRESS        PORTS     AGE
nginx   <none>   nginx.test.org   10.10.39.200   80, 443   2d
```

Let's check that this ingress has been picked up and inserted into etcd by
external dns:

```bash
k -n external-dns logs -f external-dns-96d9fbc64-j22pf
time="2020-05-12T15:23:52Z" level=info msg="Add/set key /skydns/org/test/nginx/4781436c to Host=10.10.39.200, Text=\"heritage=external-dns,external-dns/owner=default,external-dns/resource=ingress/demo/nginx\", TTL=0"
```

External DNS appears to be doing its job. Now let's see if we can resolve a
query from CoreDNS directly because it is supposed to be reading from the same
etcd server.

CoreDNS is listening with a `NodePort` service which mean we can query any nodes
on the service `NodePort`:

```bash
k -n external-dns get svc coredns-coredns
NAME                 TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)                     AGE
coredns-coredns      NodePort    10.99.62.135   <none>        53:31071/UDP,53:30396/TCP   2d1h
```

The 53 UDP port is mapped to port 31071. Let's pick a random node:

```bash
NAME STATUS   ROLES    AGE   VERSION   INTERNAL-IP    EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
m1   Ready    master   15d   v1.18.2   10.10.40.10    <none>        Ubuntu 18.04.3 LTS   4.15.0-99-generic   containerd://1.3.4
n1   Ready    <none>   15d   v1.18.2   10.10.40.110   <none>        Ubuntu 18.04.3 LTS   4.15.0-99-generic   containerd://1.3.4
n2   Ready    <none>   15d   v1.18.2   10.10.40.120   <none>        Ubuntu 18.04.3 LTS   4.15.0-74-generic   containerd://1.3.4
```

And try to make a DNS query with `dig`:

```bash
root@inf-k8s-epi-m5:~# dig -p 31071 nginx.test.org @10.10.40.120

; <<>> DiG 9.11.3-1ubuntu1.11-Ubuntu <<>> -p 31071 nginx.test.org @10.10.40.120
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 61245
;; flags: qr aa rd; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1
;; WARNING: recursion requested but not available

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 4096
; COOKIE: ef8ff2732b2dc6fd (echoed)
;; QUESTION SECTION:
;nginx.test.org.                        IN      A

;; ANSWER SECTION:
nginx.test.org.         30      IN      A       10.10.39.200

;; Query time: 2 msec
;; SERVER: 10.10.40.120#31071(10.10.40.120)
;; WHEN: Thu May 14 16:26:07 UTC 2020
;; MSG SIZE  rcvd: 85
```

We can see that CoreDNS is replying with our Metal Lb load balancer IP.

### Quickly get up and running

Throughout this guide, we set up CoreDNS, External DNS, Nginx Ingress and Metal
LB, to provide a dynamics experience like the one provided with Cloud
architecture. If you want to get started quickly, [check out our Flux repository
with all the manifest used for this demo and
more](https://github.com/clusterfrak-dynamics/gitops-template/tree/master/flux).

[**Kevin Lefevre**](https://www.linkedin.com/in/kevinlefevre/)
