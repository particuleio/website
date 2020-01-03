---
lang: fr
Title: Introduction aux PetSet et bootstrap d'un cluster Consul
Date: 2016-08-22
Category: Kubernetes
Series:  Kubernetes deep dive
Summary: Les PetSets, apparus avec la version 1.3 de Kubernetes sont des ressources qui vont permettre de gérer plus aisément les applications stateful.
Author: Kevin Lefevre
image: images/thumbnails/kubernetes.png
---

<center><img src="/images/docker/kubernetes.png" alt="coreos" width="400" align="middle"></center>

Pour continuer dans la série des fonctionnalités Alpha/Beta de Kubernetes, après [Torus](https://blog.osones.com/presentation-de-torus-un-systeme-de-fichier-distribue-cloud-natif.html), nous allons aujourd'hui tester un nouvel objet : les PetSet, qui vont permettre de manager plus facilement des applications stateful au sein d'un cluster Kubernetes. Pour valider tout cela, nous ferons un petit test en bootstrappant (du verbe bootstrapper) un cluster Consul qui rentre parfaitement dans le cas d'utilisation des PetSet.


<br />
# Les PetSets, pourquoi ?

Les pods Kubernetes sont des unités éphémères disposant potentiellement d'un cycle de vie très court et sont à la base destinés à des applications stateless. Ils disposent d'un nom aléatoire et n'ont pas d'identité propre. Ce mode de fonctionnement rend difficile l'instantiation d'applications stateful fonctionnant en cluster, comme par exemple les systèmes de stockage clé/valeurs tels que Consul, Etcd ou Zookeeper, et les bases de données comme PostgreSQL ou MySQL. Les applications clusterisées nécessitent souvent une identité propre : en général, un membre du cluster ne peut pas être remplacer aussi facilement que simplement en lançant un autre conteneur.

Dans le monde du IaaS, par exemple sur OpenStack, on parle souvent de Pet vs Cattle. Pet, dans le sens VM qui fait fonctionner une application stateful, dont on s'occupe, qui a une identité propre et n'est pas facilement remplaçable. Cattle dans le sens instance, qui sont souvent stateless et sont remplaçables de la même façon que les pods Kubernetes.

Les PetSet sont similaires aux *deployment* et *replication controller* mais proposent de nouvelles fonctionnalités :

- Identité propre au Pods :
    - Noms de domaine stables et non plus aléatoires.
    - Index ordinal (eg. consul-0, consul-1, consul-2).
    - Stockage persistent associé au nom de domaine et à l'index.
- Facilite la gestion des applications en cluster :
    - Ordre de démarrage des Pods.
    - Découverte des pairs.



<br />
<center>
<a href="http://bit.ly/ContactezOsones"><img src="/images/campagnes-osones/contactezosones.png" alt="Contactez des Experts AWS certifiés !" align="middle"></center>
</a>



<br />
# Avant les PetSets

Il est bien sur déjà possible d'utiliser de telles applications, par exemple via l'utilisation de *DaemonSet* (pour faire fonctionner un pod par nœud) ou de *deployment*, puis combiner à ce que l'on appelle un service *headless* (sans clusterIP ou NodePort).

Les services *headless* permettent de renvoyer via DNS directement les IP des pods (*endpoints*) et non la ClusterIP ou l'adresse du nœud.

Par exemple si l'on prend 2 services et leurs endpoints :

```
kubectl get endpoints
NAME         ENDPOINTS                                       AGE
consul       10.2.38.12:8500,10.2.55.8:8500,10.2.81.8:8500   4m
kubernetes   10.0.0.50:443                                   2d

```

Exemple de service :

```
kubectl describe svc kubernetes
Name:                   kubernetes
Namespace:              default
Labels:                 component=apiserver
                        provider=kubernetes
Selector:               <none>
Type:                   ClusterIP
IP:                     10.3.0.1
Port:                   https   443/TCP
Endpoints:              10.0.0.50:443
Session Affinity:       ClientIP
No events.
```

Exemple de service *headless* (ClusterIP: None) :

```
kubectl describe svc consul
Name:                   consul
Namespace:              default
Labels:                 name=consul
Selector:               daemon=consul
Type:                   ClusterIP
IP:                     None
Port:                   consul-http     8500/TCP
Endpoints:              10.2.38.12:8500,10.2.55.8:8500,10.2.81.8:8500
Session Affinity:       None
No events.
```

Dans un pod, il est possible d'interroger le *discovery service* via DNS pour résoudre les services.

Dans le cas d'un service "classique", l'IP retournée est celle du cluster :

```
nslookup kubernetes.default.svc.cluster.local

Name:      kubernetes.default.svc.cluster.local
Address 1: 10.3.0.1 kubernetes.default.svc.cluster.local
```

Dans le cas d'un service *headless*, les IPs des endpoints (pods) sont retournées directement :

```
nslookup consul.default.svc.cluster.local

Name:      consul.default.svc.cluster.local
Address 1: 10.2.38.12 consul-0u8iz
Address 2: 10.2.55.8 ip-10-2-55-8.eu-west-1.compute.internal
Address 3: 10.2.81.8 ip-10-2-81-8.eu-west-1.compute.internal
```

Avec cette technique, il est possible de bootstrapper facilement un cluster consul par exemple avec le [*DeamonSet*](https://raw.githubusercontent.com/ArchiFleKs/k8s-ymlfiles/master/consul-daemonset.yml) suivant :

```
---
apiVersion: v1
kind: Service
metadata:
  labels:
    name: consul
  name: consul
spec:
  clusterIP: None
  ports:
    - port: 8500
      name: consul-http
      targetPort: consul-http
  selector:
    daemon: consul
---
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: consul
  labels:
    app: consul
spec:
  template:
    metadata:
      name: consul
      labels:
        daemon: consul
    spec:
      containers:
      - name: consul
        image: consul
        imagePullPolicy: Always
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
          - "consul"
          - "-ui"
        ports:
        - name: consul-http
          containerPort: 8500
        volumeMounts:
        - name: consul-data
          mountPath: /data
        - name: ca-certificates
          mountPath: /etc/ssl/certs
        env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
      volumes:
      - name: consul-data
        emptyDir: {}
      - name: ca-certificates
        hostPath:
          path: /usr/share/ca-certificates/
```

Création et vérification des pods :

```
kubectl create -f consul-daemonset.yml

kubectl get pods
NAME           READY     STATUS    RESTARTS   AGE
consul-0u8iz   1/1       Running   0          6d
consul-cg2ta   1/1       Running   0          6d
consul-zajix   1/1       Running   0          6d
```

Avec un port forward on vérifie l'état du cluster consul :

```
kubectl port-forward consul-0u8iz 8400:8400 > /dev/null &1
[1] 22190

consul members
Node          Address          Status  Type    Build  Protocol  DC
consul-0u8iz  10.2.38.12:8301  alive   server  0.6.4  2         dc1
consul-cg2ta  10.2.55.8:8301   alive   server  0.6.4  2         dc1
consul-zajix  10.2.81.8:8301   alive   server  0.6.4  2         dc1
```

Que se passe t-il si l'on perd un pod ?

```
kubectl get pods
NAME           READY     STATUS    RESTARTS   AGE
consul-0u8iz   1/1       Running   0          6d
consul-cg2ta   1/1       Running   0          6d
consul-zajix   1/1       Running   0          6d

kubectl delete pods consul-cg2ta
pod "consul-cg2ta" deleted

kubectl get pods
NAME           READY     STATUS              RESTARTS   AGE
consul-0u8iz   1/1       Running             0          6d
consul-ixddk   0/1       ContainerCreating   0          3s
consul-zajix   1/1       Running             0          6d

consul members
Node          Address          Status  Type    Build  Protocol  DC
consul-0u8iz  10.2.38.12:8301  alive   server  0.6.4  2         dc1
consul-cg2ta  10.2.55.8:8301   failed  server  0.6.4  2         dc1
consul-ixddk  10.2.55.9:8301   alive   server  0.6.4  2         dc1
consul-zajix  10.2.81.8:8301   alive   server  0.6.4  2         dc1
```

Le cluster récupère correctement mais on remarque que le nouveau Pod apparaît comme un nouveau membre du cluster. Consul ne supprimant pas automatiquement les membres, au fur et à mesure de la vie des pods, on peut se retrouver avec un liste très longue de membres en erreur.

Les PetSet permettent de palier à ce problème dans le sens ou le nouveau pod disposera de la même identité que l'ancien pod, considéré comme le même membre du cluster.

<br />
# PetSet, demo

La ressource *PetSet* est disponible dans l'API apps/v1alpha1, les options de configurations sont similaires au *DeamonSet* avec en plus des options de [bootstrap](http://kubernetes.io/docs/user-guide/petset/bootstrapping/) dont on parlera dans un prochain article. Ci dessous le [*PetSet* Consul](https://raw.githubusercontent.com/ArchiFleKs/k8s-ymlfiles/master/consul-petset.yml) :

```
apiVersion: v1
kind: Service
metadata:
  name: consul
  labels:
    app: consul
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
    app: consul
---
apiVersion: apps/v1alpha1
kind: PetSet
metadata:
  name: consul
spec:
  serviceName: "consul"
  replicas: 3
  template:
    metadata:
      labels:
        app: consul
      annotations:
        pod.alpha.kubernetes.io/initialized: "true"
    spec:
      terminationGracePeriodSeconds: 0
      containers:
      - name: consul
        imagePullPolicy: Always
        image: consul
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
        - "consul"
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
        - name: consul-data
          mountPath: /data
        env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
      volumes:
      - name: consul-data
        emptyDir: {}
      - name: ca-certificates
        hostPath:
          path: /usr/share/ca-certificates/
```

Création et vérification des pets :

```
kubectl create -f consul-petset.yml
service "consul" created
petset "consul" created

kubectl get pods
NAME       READY     STATUS    RESTARTS   AGE
consul-0   1/1       Running   0          2m
consul-1   1/1       Running   0          2m
consul-2   1/1       Running   0          2m
```

Le nom des pods n'est plus aléatoire contrairement à l'utilisation d'un *daemonset*. Petit coup d'œil sur les endpoints :

```
kubectl describe endpoints consul
Name:           consul
Namespace:      default
Labels:         app=consul
Subsets:
  Addresses:            10.2.38.15,10.2.55.12,10.2.81.12
  NotReadyAddresses:    <none>
  Ports:
    Name        Port    Protocol
    ----        ----    --------
    rpc         8400    TCP
    serflan     8301    TCP
    http        8500    TCP
    server      8300    TCP
    consuldns   8600    TCP
    serfwan     8302    TCP

No events.
```

Vérification de l'état du cluster Consul :

```
consul members
Node      Address          Status  Type    Build  Protocol  DC
consul-0  10.2.81.12:8301  alive   server  0.6.4  2         dc1
consul-1  10.2.38.15:8301  alive   server  0.6.4  2         dc1
consul-2  10.2.55.12:8301  alive   server  0.6.4  2         dc1
```

Que se passe t-il maintenant si l'on perd un Pet :

```
kubectl delete pods consul-2
pod "consul-2" deleted

consul members
Node      Address          Status  Type    Build  Protocol  DC
consul-0  10.2.81.12:8301  alive   server  0.6.4  2         dc1
consul-1  10.2.38.17:8301  alive   server  0.6.4  2         dc1
consul-2  10.2.55.12:8301  failed  server  0.6.4  2         dc1

consul members
Node      Address          Status  Type    Build  Protocol  DC
consul-0  10.2.81.12:8301  alive   server  0.6.4  2         dc1
consul-1  10.2.38.17:8301  alive   server  0.6.4  2         dc1
consul-2  10.2.55.13:8301  alive   server  0.6.4  2         dc1
```

Peu de temps après, le nouveau pod remonte et récupère l'identité du précèdent. Pour Consul, c'est le même membre du Cluster. Il est possible d'allier les PetSet avec des *Persistent Volume* et *Claim* afin d'offrir du stockage persistent au Pets. Dans le cas de Consul, les données étant répliquées, perdre un Pet Consul ainsi que son volume éphémère n'a pas d'impact.

<br />
# Limitations et évolutions

La fonctionnalité est toujours en Alpha pour le moment mais elle évolue rapidement. Il existe toujours certaines limitations :

- La suppression du PetSet n'entraine pas la suppression des Pets, cette fonctionnalité/limitation est intrinsèque à la qualification de Pet (ne peut pas être supprimé par erreur aussi simplement qu'un pod). Les Pets doivent être supprimés à la main.

- Idem pour le scale down, les volumes persistants associés au pets ne seront pas supprimés sauf si la [*Claim*](http://kubernetes.io/docs/user-guide/persistent-volumes/) correspondante est supprimée (nous reviendrons dans un prochain article sur les Volumes plus en détails.

- La mise à jour est elle aussi manuelle, il faut soit démarrer un nouveau PetSet, soit sortir les Pets du PetSet, les mettre à jour puis les réintégrer au cluster. La fonctionnalité de rolling-update déjà existante pour d'autres objets est [bientôt prévue](https://github.com/kubernetes/kubernetes/issues/28706).

<br />
# Conclusion

Cette fonctionnalité, couplée aux fonctionnalités stables existantes (services discovery et services) ainsi qu'au futur [*Dynamic Volume Provisionning*](https://github.com/kubernetes/kubernetes/blob/release-1.3/examples/experimental/persistent-volume-provisioning/README.md) vont permettre de bootstrapper des services stateful quasi plus facilement sur des COE (*Containers Orchestration Engine*, tel que Kubernetes) que directement sur du IaaS, par exemple sur OpenStack ou les services de discovery et DNS tel que Designate ne sont pas encore au point.

Kubernetes fonctionne déjà sur de multiples Cloud Provider et avec la [fédération de Cluster](https://github.com/kubernetes/kubernetes/blob/release-1.3/docs/design/federation-phase-1.md) qui arrive, on se rapproche doucement d'une plate-forme multi Cloud pouvant faire fonctionner de multiples workloads, indépendamment de la nature de l'application (stateful ou stateless). Il y a beaucoup de débat autour du support ou non des Pets, notamment au sein de la communauté OpenStack et Kubernetes. Qu'elles soient Cloud Native ou pas, les applications stateful existent et sont nécessaires, c'est une réalité.


**Kevin Lefevre - [@ArchiFleKs](https://twitter.com/ArchiFleKs)**
