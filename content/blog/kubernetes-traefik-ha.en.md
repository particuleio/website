---
Title: Træfɪk and Let's Encrypt at scale with Kubernetes
lang: en
Date: 2017-03-02
Category: Kubernetes
Series:  Kubernetes deep dive
Summary: Still talking about Træfɪk, and how to manage ingress controller at scale on Kubernetes
Author: Kevin Lefevre
image: images/thumbnails/kubernetes.png
---

<center><img src="/images/docker/kubernetes.png" alt="Kubernetes" width="400" align="middle"></center>

We already talked about Træfɪk (you can check out the Kubernetes articles series linked above :) ) and how to use it as an Ingress Controller for Kubernetes. We also added Let's Encrypt.

Today we are going to talk about running Træfɪk at scale on a Kubernetes cluster, the issues with Let's Encrypt and how Træfɪk with a K/V store can solve this.

### Scaling Traefik ?

Why scale Træfɪk ? Well, for availability of course and to load balance traffic across Træfɪk pods. This is especially true when you start scaling your Kubernetes nodes.

As an ingress controller, Træfɪk can be scaled easily, either as a Kubernetes [*DaemonSet*](https://kubernetes.io/docs/admin/daemons/) or as a [*Deployment*](https://kubernetes.io/docs/user-guide/deployments/).

If you can share the TLS certs and the configuration (via *ConfigMap*) between all the Træfɪk pods there is no issues at all, we have been doing that with nginx or haproxy for a long time...

#### Adding Let's Encrypt ?

When you add Let's Encrypt into the mix, it gets more complicated: Kubernetes [*Services*](https://kubernetes.io/docs/user-guide/services/) load balances traffic between Træfɪk pods and Let's Encrypt is trying to do server side validation. Basically the route between Let's Encrypt and Træfɪk pods will be random and asymmetric.

Let's Encrypt can use server side validation before issuing a certificate, how does it works ? There is a challenge/response between Let's Encrypt and Træfɪk, this challenge has to be store inside Træfɪk at some point and if you have more than one Træfɪk pods, the pod negotiating with Let's Encrypt might change and the all thing fails.

Let's Encrypt data and certificates are stored into a file `acme.json` by default. To be able to scale Traefik, this file has to be accessible to all Træfɪk pods. I tried scaling multiples Kubernetes node with EFS an AWS but it was not fast enough and the challenge still fails.

Anyway this is not really a Cloud native solution neither a scalable one so how to solve this ?

#### Træfɪk HA

Træfɪk is a cloud reverse proxy ! As advertise, it can plug itself to several backends (Consul, etcd, Swarm ...) to handle automatic L7 routing. One other awesome feature is that it can also [store its own configuration](https://docs.traefik.io/user-guide/cluster/) (the `traefik.toml` file) inside a K/V store like Consul or Etcd and work in HA cluster mode.

With this you can have a centralized configuration store for Træfɪk. You can also store your Let's Encrypt certificates inside this K/V store so any pod can handle traffic, ask for certificates and renew the old ones. Certificates,challenges and configurations are shared thanks to the K/V store.

### Demo on Kubernetes

We are going to use Consul as there is [a bug](https://github.com/containous/traefik/issues/926) with Træfɪk / libkv and etcd at the moment.

#### Consul StatefulSet

To deploy a Consul Cluster, we are going to use a [*StatefulSet*](https://kubernetes.io/docs/concepts/abstractions/controllers/statefulsets/) which is the evolution of [*PetSet*](https://kubernetes.io/docs/user-guide/petset/) (now in beta and not alpha anymore, yeah !) that we already [discussed in french on the blog](https://blog.osones.com/kubernetes-introduction-aux-petset-et-bootstrap-dun-cluster-consul.html).

A [`Statefulset`](https://kubernetes.io/docs/concepts/abstractions/controllers/statefulsets/) is a Kubernetes Object design to run stateful application with persistent storage.

The storage is backed on AWS EBS which is the block storage service for AWS. With this, if the cluster fail or reboot, Consul pods will recover the data by remounting the volume directly from AWS. The automatic storage provisionning is done with [Kubernetes dynamic storage and EBS driver](http://blog.kubernetes.io/2016/10/dynamic-provisioning-and-storage-in-kubernetes.html).

Here is the manifest for the StatefulSet:

```yaml
apiVersion: v1
kind: Service
metadata:
  namespace: kube-system
  name: traefik-consul
  labels:
    app: traefik-consul
spec:
  ports:
    - name: http
      port: 8500
    - name: rpc
      port: 8400
    - name: serflan
      port: 8301
    - name: serfwan
      port: 8302
    - name: server
      port: 8300
    - name: consuldns
      port: 8600
  clusterIP: None
  selector:
    app: traefik-consul
---
apiVersion: apps/v1beta1
kind: StatefulSet
metadata:
  namespace: kube-system
  name: traefik-consul
spec:
  serviceName: "traefik-consul"
  replicas: 3
  template:
    metadata:
      labels:
        app: traefik-consul
    spec:
      terminationGracePeriodSeconds: 0
      containers:
      - name: traefik-consul
        imagePullPolicy: Always
        image: consul:0.7.5
        args:
        - "agent"
        - "-server"
        - "-client"
        - "0.0.0.0"
        - "-recursor"
        - "8.8.8.8"
        - "-bootstrap-expect"
        - "3"
        - "-retry-join"
        - "traefik-consul"
        - "-ui"
        ports:
        - containerPort: 8500
          name: ui-port
        - containerPort: 8400
          name: alt-port
        - containerPort: 53
          name: udp-port
        - containerPort: 443
          name: https-port
        - containerPort: 8080
          name: http-port
        - containerPort: 8301
          name: serflan
        - containerPort: 8302
          name: serfwan
        - containerPort: 8600
          name: consuldns
        - containerPort: 8300
          name: server
        volumeMounts:
        - name: ca-certificates
          mountPath: /etc/ssl/certs
        - name: traefik-consul-data
          mountPath: /data
        env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
      volumes:
      - name: ca-certificates
        hostPath:
          path: /usr/share/ca-certificates/
  volumeClaimTemplates:
  - metadata:
      name: traefik-consul-data
      annotations:
        volume.beta.kubernetes.io/storage-class: "ebs"
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 1Gi
```

```bash
kubectl apply -f consul-statefulset.yaml
```

This bootstrap a 3 nodes Consul cluster on Kubernetes which we are going to use as Træfɪk backend to store its configuration.

### Preparing Træfɪk

Once the K/V store is OK we have to tell Træfɪk to store its configuration inside Consul. To do so we are running a [*job*](https://kubernetes.io/docs/user-guide/jobs/) to initialize the K/V with the right configuration.

We have:

* A static [`configmap`](https://kubernetes.io/docs/user-guide/configmap/) that Træfɪk will use to populate Consul:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: kube-system
  name: traefik-conf
data:
  traefik.toml: |
    # traefik.toml
    logLevel = "DEBUG"
    defaultEntryPoints = ["http","https"]
    [entryPoints]
      [entryPoints.http]
      address = ":80"
      [entryPoints.http.redirect]
      entryPoint = "https"
      [entryPoints.https]
      address = ":443"
      [entryPoints.https.tls]
    [kubernetes]
    [web]
    address = ":8080"
    [acme]
    email = "contact@osones.com"
    storage = "traefik/acme/account"
    entryPoint = "https"
    onDemand = true
    onHostRule = true
    [[acme.domains]]
    main = "archifleks.xyz"
    [consul]
    endpoint = "traefik-consul:8500"
    watch = true
    prefix = "traefik"
```

```bash
kubectl apply -f traefik-configmap.yaml
```

* A job that runs a one time Træfɪk instance to populate the K/V Store:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: traefik-kv-job
  namespace: kube-system
spec:
  template:
    metadata:
      name: traefik-kv-jobs
    spec:
      containers:
        - image: containous/traefik:v1.1.2
          name: traefik-ingress-lb
          imagePullPolicy: Always
          volumeMounts:
            - mountPath: "/config"
              name: "config"
          ports:
            - containerPort: 80
            - containerPort: 443
            - containerPort: 8080
          args:
            - storeconfig
            - --configfile=/config/traefik.toml
      volumes:
        - name: config
          configMap:
            name: traefik-conf
      restartPolicy: Never
```

```bash
kubectl apply -f traefik-kv-jobs.yaml
```

With this job, the static configuration from Configmap is stored into Consul, now we don't need it anymore, we just have to tell Træfɪk to use etcd instead.

#### Deploying Træfɪk

There is one small bug with Consul, the first time Traefik populate the K/V Store, it creates a key that needs to be deleted manually (https://github.com/containous/traefik/issues/927). This is a one time thing during the initialization and should be fixed upstream.

```bash
kubectl --namespace kube-system exec -it traefik-consul-0 consul kv delete traefik/acme/storagefile
```

Once this is done we can deploy Træfɪk with a *Service* and a *Deployment*. In this example, we are using an AWS ELB that will route internet traffic to Træfɪk Kubernetes service.

Instead of using `services` with AWS ELB Load Balancing feature for each application, we are going to use internal services instead : only Traefik will have an External Service of type [*LoadBalancer*](https://kubernetes.io/docs/user-guide/load-balancer/).

With this, we can reduce the number of ELB needed and AWS cost. We also manage virtual host with Kubernetes [*Ingress Resources*](https://kubernetes.io/docs/user-guide/ingress/) and no manual configuration. Also, services are not directly exposed, only Træfɪk and you get to manage the reverse proxy and the TLS setup with Kubernetes only ! :)

```yaml
---
apiVersion: v1
kind: Service
metadata:
  namespace: kube-system
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
  type: LoadBalancer
---
apiVersion: v1
kind: Service
metadata:
  namespace: kube-system
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
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  namespace: kube-system
  name: traefik-ingress-controller
  labels:
    k8s-app: traefik-ingress-lb
spec:
  replicas: 3
  template:
    metadata:
      labels:
        k8s-app: traefik-ingress-lb
        name: traefik-ingress-lb
    spec:
      containers:
        - image: containous/traefik:v1.1.2
          name: traefik-ingress-lb
          imagePullPolicy: Always
          ports:
            - containerPort: 80
            - containerPort: 443
            - containerPort: 8080
          args:
            - --consul
            - --consul.endpoint=traefik-consul:8500
```

```bash
kubectl apply -f traefik-kv.yaml
```

With this, 3 Træfɪk replicas are spawned, all using Consul to store cluster state and Let's Encrypt data.

#### Using Træfɪk

To use Træfɪk, we are going to use [*Ingress Resources*](https://kubernetes.io/docs/user-guide/ingress/) from the Kubernetes API. We already discussed this [in a previous article](https://blog.osones.com/en/kubernetes-ingress-controller-with-traefik-and-lets-encrypt.html).

```yaml
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  namespace: default
  name: sickrage
  annotations:
    kubernetes.io/ingress.class: "traefik"
spec:
  rules:
    - host: sickrage.archifleks.net
      http:
        paths:
          - backend:
              serviceName: jenkins
              servicePort: 80
```

```
kubectl apply -f ingress.yaml
```

Træfɪk is watching the Kubernetes API for ingresses and automatically does the routing and gets the TLS certificates from Lets Encrypt.

#### About namespaces and Ingress Controller

It is important to note that even though *Ingress* resources are [namespaced](https://kubernetes.io/docs/user-guide/namespaces/), this is not the case for the ingress controller.

It means that Træfɪk and Consul are deployed within the kube-system namespace, which might be admin managed but you can create services and ingresses in every namespace (might be user managed namespaces) that will use the global ingress controller for the cluster.

Træfɪk is watching for ingresses and services across namespaces so if the right domain is configured within Træfɪk configuration and is used by the user, they will be issued a certificate seamlessly without any manual intervention, without even seeing Træfɪk or the Consul Service.

If we have a look at the kube-system namespace:

```bash
kubectl --kubeconfig kubeconfig --namespace kube-system get all                                                                                                             master 
NAME                                                                  READY     STATUS    RESTARTS   AGE
po/calico-node-828fc                                                  2/2       Running   0          7d
po/calico-node-9vqph                                                  2/2       Running   0          7d
po/calico-node-fdb1v                                                  2/2       Running   0          7d
po/calico-node-g98xt                                                  2/2       Running   0          6d
po/calico-policy-controller-3161050834-hsct8                          1/1       Running   0          7d
po/heapster-v1.2.0-4088228293-q74m9                                   2/2       Running   0          7d
po/kube-apiserver-ip-10-0-1-161.eu-west-1.compute.internal            1/1       Running   0          7d
po/kube-controller-manager-ip-10-0-1-161.eu-west-1.compute.internal   1/1       Running   0          7d
po/kube-dns-782804071-b42jj                                           4/4       Running   0          7d
po/kube-dns-782804071-p2gsd                                           4/4       Running   0          7d
po/kube-dns-autoscaler-2813114833-1w272                               1/1       Running   0          7d
po/kube-proxy-ip-10-0-0-201.eu-west-1.compute.internal                1/1       Running   0          7d
po/kube-proxy-ip-10-0-1-161.eu-west-1.compute.internal                1/1       Running   0          7d
po/kube-proxy-ip-10-0-1-63.eu-west-1.compute.internal                 1/1       Running   0          7d
po/kube-proxy-ip-10-0-2-151.eu-west-1.compute.internal                1/1       Running   0          6d
po/kube-scheduler-ip-10-0-1-161.eu-west-1.compute.internal            1/1       Running   0          7d
po/kubernetes-dashboard-v1.5.0-jsf3f                                  1/1       Running   0          7d
po/kubernetes-dashboard-v1.5.1-wr8v5                                  1/1       Running   0          7d
po/traefik-consul-0                                                   1/1       Running   0          6d
po/traefik-consul-1                                                   1/1       Running   0          6d
po/traefik-consul-2                                                   1/1       Running   0          6d
po/traefik-ingress-controller-1802447368-3d46q                        1/1       Running   0          6d
po/traefik-ingress-controller-1802447368-4lxwc                        1/1       Running   0          6d
po/traefik-ingress-controller-1802447368-g9x8x                        1/1       Running   0          6d

NAME                             DESIRED   CURRENT   READY     AGE
rc/kubernetes-dashboard-v1.5.0   1         1         1         50d
rc/kubernetes-dashboard-v1.5.1   1         1         1         7d

NAME                       CLUSTER-IP   EXTERNAL-IP        PORT(S)                                                 AGE
svc/heapster               10.3.0.159   <none>             80/TCP                                                  50d
svc/kube-dns               10.3.0.10    <none>             53/UDP,53/TCP                                           50d
svc/kubernetes-dashboard   10.3.0.87    <none>             80/TCP                                                  50d
svc/traefik                10.3.0.194   a0a042d71f9dd...   80:30765/TCP,443:30606/TCP                              6d
svc/traefik-console        10.3.0.182   <none>             8080/TCP                                                6d
svc/traefik-consul         None         <none>             8500/TCP,8400/TCP,8301/TCP,8302/TCP,8300/TCP,8600/TCP   6d

NAME                          DESIRED   CURRENT   AGE
statefulsets/traefik-consul   3         3         6d

NAME                  DESIRED   SUCCESSFUL   AGE
jobs/traefik-kv-job   1         1            6d

NAME                                DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
deploy/calico-policy-controller     1         1         1            1           7d
deploy/heapster-v1.2.0              1         1         1            1           50d
deploy/kube-dns                     2         2         2            2           50d
deploy/kube-dns-autoscaler          1         1         1            1           50d
deploy/traefik-ingress-controller   3         3         3            3           6d

NAME                                       DESIRED   CURRENT   READY     AGE
rs/calico-policy-controller-3161050834     1         1         1         7d
rs/heapster-v1.2.0-3646253287              0         0         0         50d
rs/heapster-v1.2.0-4088228293              1         1         1         50d
rs/kube-dns-782804071                      2         2         2         50d
rs/kube-dns-autoscaler-2813114833          1         1         1         50d
rs/traefik-ingress-controller-1802447368   3         3         3         6d
```

We can see the resources we created. But if you look at another namespace using ingress:

```bash
kubectl --kubeconfig kubeconfig --namespace user-manage-namespace get all
NAME                                READY     STATUS    RESTARTS   AGE
po/app-3326329437-37ld3             1/1       Running   0          7d
po/aoo-3326329437-q2hv6             1/1       Running   0          7d

NAME                CLUSTER-IP   EXTERNAL-IP                                           PORT(S)    AGE
svc/mysql                        mysql.rds.amazonaws.com   3306/TCP   48d
svc/app             10.3.0.169   <none>                                                80/TCP     7d

NAME                REFERENCE                  TARGET    CURRENT   MINPODS   MAXPODS   AGE
hpa/app             Deployment/app   60%       0%        2         10        7d

NAME                   DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
deploy/app             2         2         2            2           7d

NAME                          DESIRED   CURRENT   READY     AGE
rs/app-3326329437             2         2         2         7d

kubectl --kubeconfig kubeconfig --namespace preprod get ingress
NAME            HOSTS                         ADDRESS   PORTS     AGE
app             app.archifleks.xyz            80        7d
```
You have no idea of the ingress controller or other resources running inside the kube-system namespace. But you stil get your reverse proxy automatically :)

### Conclusion

With this solution, we are able to run Traefik at scale on Kubernetes cluster by either using a DaemonSet where you can have one Træfɪk instance on each nodes or a Deployment like in this example where you can manage the numbers of replicas. You can even add an [horizontal pod scaler](https://kubernetes.io/docs/user-guide/horizontal-pod-autoscaling/) to scale Træfɪk pods automatically.

We are also able to provide a global reverse proxy service with automatic TLS support via Let's Encrypt to users. This provides a single secured entrypoint for services without having to publish and secure each application.
