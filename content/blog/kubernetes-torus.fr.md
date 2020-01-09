---
lang: fr
Title: Présentation de Torus, un système de fichier distribué cloud natif
Date: 2016-07-11
Category: Kubernetes
Series:  Kubernetes deep dive
Summary: Osones vous présente Torus, un système de fichier distribué cloud natif basé sur etcd
Author: Kevin Lefevre
image: images/thumbnails/kubernetes.png
---

<center><img src="/images/docker/kubernetes.png" alt="coreos" width="400" align="middle"></center>

On continue dans la série Kubernetes avec un article sur Torus, un système de fichier distribué cloud-natif développé par CoreOS qui offre un stockage redondant et persistant aux pods Kubernetes.

### Qu'est-ce que Torus ?

Dans l'écosystème conteneurs, le stockage persistant reste un problème majeur : les applications stateless se conteneurisent facilement et n'ont généralement pas besoin de données persistantes. Ce n'est pas le cas des applications stateful telles que les bases de données par exemple. Dans l'écosystème Docker, il existe déjà des plugins de stockage basés sur des technologies diverses :

- GlusterFS
- NFS
- [Convoy](https://github.com/rancher/convoy) (qui présente GlusterFS ou NFS (ainsi que d'autres backends) à Docker)

Du côté des volumes Kubernetes, de nombreux backends sont supportés :

- iSCSI
- GlusterFS
- rbd (Ceph)
- NFS
- Volumes basés sur le Cloud Provider (GCE PD, AWS EBS, Azure Volume)

À l'exception des backends Cloud Providers, la plupart peuvent être relativement lourds à mettre en place (comme Ceph), ou à scaler dans une infrastructure cloud native orientée conteneurs et constituée d'un nombre conséquent de "petites" machines (GlusterFS/NFS).

En juin 2016, CoreOS a annoncé la création d'un nouveau système de fichier distribué : Torus, qui a pour but de fournir du stockage distribué cloud natif.

<center><img src="/images/torus.svg" alt="Torus" width="500" align="middle"></center>

Dans la philosophie micro services et GIFEE (*Google Infrastructure For Everyone Else*) de CoreOS, Torus, se concentre sur le stockage ; les parties metadata et consensus sont déléguées à *etcd* : un key/value store hautement scalable utilisé en production par des solutions comme Kubernetes et Docker Swarm. Torus supporte ainsi les fonctionnalités classiques des systèmes de fichiers distribués telles que la réplication ou la répartition équilibrée des données.

Quelles sont les différences avec GlusterFS ou NFS ? Torus fournit pour le moment uniquement un stockage de type bloc via le protocole *nbd* (Network Block Device). De part son architecture, il sera possible ensuite d'exposer d'autres types de stockage notamment de l'objet ou encore du système de fichiers (comme NFS ou GlusterFS). Torus est également écrit en Go, compilé statiquement, ce qui le rend facilement portable et conteneurisable. Torus se décompose en 3 binaires :

- *torusd* : le démon Torus
- *torusctl* : contrôle du cluster et des volumes
- *torusblk* : contrôle du montage/démontage des volumes bloc

### Intégration à Kubernetes : Flex Volume

Torus est indépendant de Kubernetes. Il peut s'installer de manière autonome et exposer ses volumes via le protocole NDB. Ces volumes peuvent ensuite être utilisés comme n'importe quel volume bloc.

Kubernetes, en plus du support de volumes built-in, dispose d'un plugin FlexVolume qui offre aux solutions de stockage tierce partie la possibilité d'implémenter un driver sans toucher au cœur de Kubernetes. Le binaire *torusblk* est compatible avec les spécifications FlexVolume de Kubernetes, ce qui permet de monter directement des volumes Torus dans des pods.

# Test sur un cluster Kubernetes : déploiement d'etherpad-lite

Ce test est réalisé sur un cluster Kubernetes 1.3, composé de 3 nœuds CoreOS dont 1 contrôleur. Nous allons déployer Torus directement via Kubernetes. Pour fonctionner, Torus a besoin :
- Du module kernel nbd sur les workers Kubernetes
- Du binaire torusblk installé dans le répertoire des drivers FlexVolume spécifié dans la configuration du Kubelet
- De etcd en version 3
- Du stockage disponible sur les workers Kubernetes

#### Installation du plugin

Les binaires de Torus sont disponibles [ici](https://github.com/coreos/torus/releases).

Tout d'abord on vérifie la configuration du [Kubelet](http://kubernetes.io/docs/admin/kubelet/) :

```bash
# /etc/systemd/system/kubelet.service
[Service]
ExecStartPre=/usr/bin/mkdir -p /etc/kubernetes/manifests

Environment=KUBELET_VERSION=v1.3.0_coreos.0
ExecStart=/usr/lib/coreos/kubelet-wrapper \
  --api-servers=http://127.0.0.1:8080 \
  --network-plugin-dir=/etc/kubernetes/cni/net.d \
  --network-plugin= \
  --register-schedulable=false \
  --allow-privileged=true \
  --config=/etc/kubernetes/manifests \
  --hostname-override=192.168.122.110 \
  --cluster-dns=10.3.0.10 \
  --cluster-domain=cluster.local \
  --volume-plugin-dir="/etc/kubernetes/kubelet-plugins/volume/exec/"
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
```

Il faut rajouter la ligne *volume-plugin-dir* si celle-ci n'est pas présente. Le chemin par défaut du Kubelet est `--volume-plugin-dir="/usr/libexec/kubernetes/kubelet-plugins/volume/exec/"` mais `/usr` est en lecture seule sur CoreOS.

Le répertoire spécifié doit être ensuite créé, avant de copier le binaire `torusblk` en le renommant `torus` sur tous les workers du cluster dans `/etc/kubernetes/kubelet-plugins/volume/exec/coreos.com~torus/` :

```bash
ansible -i ../ansible-coreos/inventory "worker*" -m file -b -a "dest=/etc/kubernetes/kubelet-plugins/volume/exec/coreos.com~torus mode=700 state=directory"
ansible -i ../ansible-coreos/inventory "worker*" -m copy -b -a "src=/home/klefevre/go/src/github.com/coreos/torus/bin/torusblk dest=/etc/kubernetes/kubelet-plugins/volume/exec/coreos.com~torus/torus mode=700"
```

Torus a également besoin du module kernel `nbd`. Il est possible de le charger à la volée :

```bash
ansible -i ../ansible-coreos/inventory -m shell -b -a "modprobe nbd" "worker*"
```

Ou par exemple pour CoreOS de le charger via cloud-init au démarrage :

```yaml
#cloud-config
write_files:
  - path: /etc/modules-load.d/nbd.conf
    content: nbd
coreos:
  units:
    - name: systemd-modules-load.service
      command: restart
```

Il faut ensuite redémarrer le Kubelet sur tous les nœuds et c'est terminé pour la partie pré-requis. Le reste se déroule uniquement sur Kubernetes :

```bash
ansible -i inventory -m shell -b -a "systemctl restart kubelet" "worker*"
```

#### Déploiement d'etcdv3

Pour fonctionner, Torus a besoin d'etcd en version 3 minimum, le service peut être déployé simplement sur Kubernetes et publié à l'aide d'un service :

```yaml
# etcdv3-daemonset.yml
---
apiVersion: v1
kind: Service
metadata:
  labels:
    name: etcdv3
  name: etcdv3
spec:
  type: NodePort
  clusterIP: 10.3.0.100
  ports:
    - port: 2379
      name: etcdv3-client
      targetPort: etcdv3-client
  selector:
    daemon: etcdv3
---
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: etcdv3
  labels:
    app: etcdv3
spec:
  template:
    metadata:
      name: etcdv3
      labels:
        daemon: etcdv3
    spec:
      containers:
      - name: etcdv3
        image: quay.io/coreos/etcd:latest
        imagePullPolicy: Always
        ports:
        - name: etcdv3-peers
          containerPort: 2380
        - name: etcdv3-client
          containerPort: 2379
        volumeMounts:
        - name: etcdv3-data
          mountPath: /var/lib/etcd
        - name: ca-certificates
          mountPath: /etc/ssl/certs
        env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: ETCD_DATA_DIR
          value: /var/lib/etcd
        - name: ETCD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: ETCD_INITIAL_ADVERTISE_PEER_URLS
          value: http://$(POD_IP):2380
        - name: ETCD_ADVERTISE_CLIENT_URLS
          value: http://$(POD_IP):2379
        - name: ETCD_LISTEN_CLIENT_URLS
          value: http://0.0.0.0:2379
        - name: ETCD_LISTEN_PEER_URLS
          value: http://$(POD_IP):2380
        - name: ETCD_DISCOVERY
          value: https://discovery.etcd.io/         #-> url de discovery à générer avant déploiement
      volumes:
      - name: etcdv3-data
        hostPath:
          path: /srv/etcdv3
      - name: ca-certificates
        hostPath:
          path: /usr/share/ca-certificates/
```

L'utilisation d'un DaemonSet permet de déployer une instance d'etcd par worker. Sur l'un des nœuds l'état du cluster peut être vérifié avec `etcdctl` via le service publié :

```bash
kubectl create -f etcdv3-daemonset.yml

kubectl get pods --selector="daemon=etcdv3"
NAME           READY     STATUS    RESTARTS   AGE
etcdv3-4jncl   1/1       Running   1          1d
etcdv3-7r46s   1/1       Running   1          1d
etcdv3-o0n86   1/1       Running   1          1d
```

```bash
core@coreos00 ~ $ etcdctl --endpoints=http://10.3.0.100:2379 cluster-health
member 3f87be33d946732d is healthy: got healthy result from http://10.2.78.2:2379
member a19d841707579e60 is healthy: got healthy result from http://10.2.36.3:2379
member d5479de5c3342460 is healthy: got healthy result from http://10.2.55.3:2379
cluster is healthy

core@coreos00 ~ $ etcdctl --endpoints=http://10.3.0.100:2379 member list
3f87be33d946732d: name=etcdv3-7r46s peerURLs=http://10.2.78.2:2380 clientURLs=http://10.2.78.2:2379 isLeader=true
a19d841707579e60: name=etcdv3-4jncl peerURLs=http://10.2.36.3:2380 clientURLs=http://10.2.36.3:2379 isLeader=false
d5479de5c3342460: name=etcdv3-o0n86 peerURLs=http://10.2.55.2:2380 clientURLs=http://10.2.55.3:2379 isLeader=false
```

#### Déploiement de Torus

Torus est aussi déployé directement sur Kubernetes, toujours via un DaemonSet qui permet d'avoir une instance de Torus par worker. Les blocs seront stockés dans un volume de l'hôte.

```yaml
# torus-daemonset.yml
---
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: torus
  labels:
    app: torus
spec:
  template:
    metadata:
      name: torus
      labels:
        daemon: torus
    spec:
      containers:
      - name: torus
        image: quay.io/coreos/torus:latest
        imagePullPolicy: Always
        ports:
        - name: torus-peer
          containerPort: 40000
        - name: torus-http
          containerPort: 4321
        env:
        - name: ETCD_HOST
          value: 10.3.0.100                         #-> Cluster
        - name: STORAGE_SIZE
          value: 5GiB                               #-> Taille maximum donnée au pool de stockage par worker
         - name: LISTEN_HOST
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: AUTO_JOIN
          value: "1"
        - name: DEBUG_INIT
          value: "1"
        - name: DROP_MOUNT_BIN
          value: "0"
        volumeMounts:
          - name: torus-data
            mountPath: /data
      volumes:
        - name: torus-data
          hostPath:
            path: /srv/torus                        #-> repertoire de l'host contenant les données des volumes Torus
```

```bash
kubectl create -f etcdv3-daemonset.yml

kubectl get pods --selector="daemon=torus"
NAME          READY     STATUS    RESTARTS   AGE
torus-56p79   1/1       Running   0          1m
torus-87f9t   1/1       Running   0          1m
torus-wc54r   1/1       Running   0          1m
```

Sur la machine qui contrôle Kubernetes, le cluster peut être contrôlé à l'aide des binaires Torus et d'un port forward vers un pod etcd :

```bash
kubectl port-forward etcdv3-4jncl
```

Il est ensuite possible de contrôler Torus localement :

```bash
torusctl list-peers
Handling connection for 2379
ADDRESS                 UUID                                  SIZE     USED  MEMBER  UPDATED        REB/REP DATA
http://10.2.55.2:40000  dce8cf72-45f5-11e6-9426-02420a023702  5.0 GiB  0 B   OK      4 seconds ago  0 B/sec
http://10.2.78.3:40000  dd53432a-45f5-11e6-8fec-02420a024e03  5.0 GiB  0 B   OK      4 seconds ago  0 B/sec
http://10.2.36.4:40000  dd800d8c-45f5-11e6-b812-02420a022404  5.0 GiB  0 B   OK      2 seconds ago  0 B/sec
Balanced: true Usage:  0.00%
```

Les 3 instances de Torus avec chacune 5 GiB dans le pool de stockage sont disponibles. Il faut ensuite créer un volume de 1 GiB pour *Etherpad* :

```bash
torusctl volume create-block pad 1GiB
torusctl volume list
Handling connection for 2379
VOLUME NAME  SIZE     TYPE
pad          1.0 GiB  block
```

Le volume est maintenant disponible et utilisable dans Kubernetes.

#### Déploiement d'Etherpad

Etherpad est déployé simplement via un `deployment` et un `service` :

```yaml
# deployment-etherpad.yml
---
apiVersion: v1
kind: Service
metadata:
    name: etherpad
    labels:
        app: etherpad
spec:
    selector:
        app: etherpad
    ports:
        - port: 80
          targetPort: etherpad-port
    type: NodePort
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: etherpad
  labels:
    app: etherpad
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: etherpad
    spec:
      containers:
      - name: etherpad
        image: "osones/etherpad:alpine"
        ports:
        - name: etherpad-port
          containerPort: 9001
        volumeMounts:
        - name: etherpad
          mountPath: /etherpad/var
        env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
      volumes:
        - name: etherpad
          flexVolume:
            driver: "coreos.com/torus"              #-> le driver pour le FlexVolume
            fsType: "ext4"
            options:
              volume: "pad"                         #-> Le nom du volume créé precedemment
              etcd: "10.3.0.100:2379"               #-> L'adresse du service etcd créé precedemment
```

Vérification du déploiement :

```bash
kubectl create -f ymlfiles/deployment-etherpad.yml
deployment "etherpad" created
service "etherpad" created

kubectl describe service etherpad
Name:                   etherpad
Namespace:              default
Labels:                 app=etherpad
Selector:               app=etherpad
Type:                   NodePort
IP:                     10.3.0.157
Port:                   <unset> 80/TCP
NodePort:               <unset> 31594/TCP
Endpoints:              10.2.55.4:9001
Session Affinity:       None
No events.
```

Pour des raisons de simplicité et en fonction de la configuration initiale, le service écoute également sur un `NodePort`, ce qui permet de joindre le service en accédant à n'importe quel worker sur le port 31594.

Pour tester la persistance des données, nous allons créer un pad nommé torus :

<center><img src="/images/etherpad-pod1.png" alt="etherpad-pod1" width="500" align="middle"></center>

L'intérêt est de marquer le nœud sur lequel fonctionne actuellement Etherpad comme non-schedulable (*cordon* dans les termes Kubernetes) puis de détruire le pod Etherpad afin de le rescheduler sur un autre nœud :

```bash
kubectl describe pods etherpad-2266423034-6wk4u
Name:           etherpad-2266423034-6wk4u
Namespace:      default
Node:           192.168.122.111/192.168.122.111
Start Time:     Sat, 09 Jul 2016 19:11:23 +0200
Labels:         app=etherpad
                pod-template-hash=2266423034
Status:         Running
IP:             10.2.55.4
Controllers:    ReplicaSet/etherpad-2266423034
...

kubectl cordon 192.168.122.111
node "192.168.122.111" cordoned

kubectl get nodes
NAME              STATUS                     AGE
192.168.122.110   Ready                      4d
192.168.122.111   Ready,SchedulingDisabled   4d
192.168.122.112   Ready                      4d
```

Le scheduling est bien désactivé sur le nœud 192.168.122.111. On détruit le pod Etherpad qui sera ensuite relancé automatiquement grâce au *replicaset* défini dans le déploiement :

```bash
kubectl get pods --selector="app=etherpad"
NAME                        READY     STATUS    RESTARTS   AGE
etherpad-2266423034-6wk4u   1/1       Running   0          14m

kubectl delete pods etherpad-2266423034-6wk4u
pod "etherpad-2266423034-6wk4u" deleted
```

Vérification du nouveau pod :

```bash
kubectl get pods --selector="app=etherpad"
NAME                        READY     STATUS    RESTARTS   AGE
etherpad-2266423034-urb2f   1/1       Running   0          1m

kubectl describe pods --selector="app=etherpad"
Name:           etherpad-2266423034-urb2f
Namespace:      default
Node:           192.168.122.112/192.168.122.112
Start Time:     Sat, 09 Jul 2016 19:25:46 +0200
Labels:         app=etherpad
                pod-template-hash=2266423034
Status:         Running
IP:             10.2.36.5
Controllers:    ReplicaSet/etherpad-2266423034
```

<center><img src="/images/etherpad-pod2.png" alt="etherpad-pod2" width="500" align="middle"></center>

Bon, j'avoue que pour les captures d'écran, je vous invite à vous baser sur la confiance.

### Conclusion

Torus est un produit très jeune qui vient s'inscrire dans la philosophie des autres produits open source lancés par CoreOS.

Si le stockage bloc a effectivement peu d'intérêt lors de l'utilisation d'un Cloud Provider puisque Kubernetes supporte déjà les PD sur GCE et les volumes EBS sur AWS, Torus va en revanche permettre, dans le cas d'une utilisation on premises ou de Cloud Providers différents, d'abstraire et d'agréger les volumes de multiples instances.

Enfin, en ce qui concerne GlusterFS et NFS, Torus ne joue pas encore sur le même terrain puisque seul le stockage bloc est aujourd'hui disponible.

Reste à voir non seulement comment le produit évolue mais également si l'engouement est au rendez-vous comme il l'a été pour CoreOS et leurs autres produits.

**Kevin Lefevre**
