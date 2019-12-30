---
Title: Torus, a cloud native distributed file system
lang: en
Date: 2016-07-11
Category: Kubernetes
Series:  Kubernetes deep dive
Summary: Discover Torus, an etcd backed distributed file system that can be use by Kubernetes FlexVolume.
Author: Kevin Lefevre
image: images/thumbnails/kubernetes.png
---

<center><img src="/images/docker/kubernetes.png" alt="coreos" width="400" align="middle"></center>

Still in the Kubernetes series, this week let's take a look at Torus, a cloud native distributed file system developed by CoreOS which give persistent storage to Kubernetes PODs.

# Qu'est-ce que Torus ?

In the container world, persistent storage is still a major issue : stateless application are easily moved to container based environment and do not usually need persistent data. This is not the case of stateful applications such as databases. For Docker, there are some plugins available already :

  * GlusterFS
  * NFS
  * [Convoy](https://github.com/rancher/convoy) (abstracts GlusterFS and NFS backends to Docker)

For Kubernetes volumes, several backends are supported :

  * iSCSI
  * GlusterFS
  * rbd (Ceph)
  * NFS
  * Volumes based on Cloud Provider (GCE PD, AWS EBS, Azure Volume)

With the exception of cloud prodiver backends, most are difficult to deploy (like ceph) or to scale in an container based infrastructue composed of small and expendables instances.

In June 2016, CoreOS annonced a new distributed file system : Torus, whose goal is to serve as cloud native distributed storage.

<center><img src="/images/torus.svg" alt="Torus" width="500" align="middle"></center>

In the spirit of micro services and GIFEE (*Google Infrastructure For Everyone Else*), Torus focuses on the storage : Metadata and consensus are enforced by *etcd* : A highly scalable key/value store used by Kubernetes or Docker Swarm. Torus supports all the features of modern file system such as replication and load balancing of data.

What are the differences with GlusterFS or NFS ? Torus provides only block storage for now via the *NBD* protocol (Network Block Device). By design, it will be possible to expose other storage types like object storage or file system. Torus is written in Go and statically linked, which makes it easily portable into containers. Torus is split into 3 binaries :

  * *torusd* : Torus daemon
  * *torusctl* : CLI to manage Torus
  * *torusblk* : CLI to manage Torus Block Devices

# Kubernetes integration with Flex Volume

Torus is independent from Kubernetes. It can be installed as a standalone application and expose volumes via NBD. These volume can then be used like any other block device.

Kubernetes, in addition to built-in volumes, has a FlexVolume plugin that allows custom storage solution to implements a storage drivers without touching the heart of Kubernetes. *torusblk* binary is compatible with FlexVolume specs so we can directly mount storage into PODs.

# Demo on a Kubernetes cluster with etherpad-lite

This test takes place on Kubernetes 1.3 cluster with 3 CoreOS nodes. We are going to deploy Torus as a container, directly on Kubernetes. To work properly Torus needs :

  * NBD kernel module loaded
  * Torus binary into the kubelet plugin directory
  * Etcd v3
  * Free storage on the nodes

## Plugin installation

Torus binaries are available [here](https://github.com/coreos/torus/releases).

First let's check [Kubelet's](http://kubernetes.io/docs/admin/kubelet/) config :

```Bash
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

We need to add `volume-plugin-dir` if not already present. Default is `--volume-plugin-dir="/usr/libexec/kubernetes/kubelet-plugins/volume/exec/"` but `/usr` is in read-only in CoreOS.

Then we need to create the directory and drop `torusblk` binary as `torus` on each node `/etc/kubernetes/kubelet-plugins/volume/exec/coreos.com~torus/` :

```Bash
ansible -i ../ansible-coreos/inventory "worker*" -m file -b -a "dest=/etc/kubernetes/kubelet-plugins/volume/exec/coreos.com~torus mode=700 state=directory"
ansible -i ../ansible-coreos/inventory "worker*" -m copy -b -a "src=/home/klefevre/go/src/github.com/coreos/torus/bin/torusblk dest=/etc/kubernetes/kubelet-plugins/volume/exec/coreos.com~torus/torus mode=700"
```

Torus also needs `nbd` kernel module. It can be loaded manually :

```Bash
ansible -i ../ansible-coreos/inventory -m shell -b -a "modprobe nbd" "worker*"
```

Or with cloud-init :

```YAML
#cloud-config
write_files:
  - path: /etc/modules-load.d/nbd.conf
    content: nbd
coreos:
  units:
    - name: systemd-modules-load.service
      command: restart
```

Finally we need to restart the Kubelet service on each node and we are done for the prerequisites. The remaining steps take place on Kubernetes :

```Bash
ansible -i inventory -m shell -b -a "systemctl restart kubelet" "worker*"
```

## Etcdv3 deployment

To work properly, Torus needs the latest etcd v3. It can be deploy on Kubernetes and publish with a service :

```YAML
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
          value: https://discovery.etcd.io/         #-> Get discovery URL before launching
      volumes:
      - name: etcdv3-data
        hostPath:
          path: /srv/etcdv3
      - name: ca-certificates
        hostPath:
          path: /usr/share/ca-certificates/
```

Usage of DeamonSet ensure that there is one instance of etcd per node. Etcd cluster state can be validated with `etcdctl` and the Kubernetes service IP :

```Bash
kubectl create -f etcdv3-daemonset.yml

kubectl get pods --selector="daemon=etcdv3"
NAME           READY     STATUS    RESTARTS   AGE
etcdv3-4jncl   1/1       Running   1          1d
etcdv3-7r46s   1/1       Running   1          1d
etcdv3-o0n86   1/1       Running   1          1d
```

```Bash
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

## Torus deployment

Torus is also deployed on top of Kubernetes, also with a DaemonSet so there is one instance of Torus on each node. That instance is using local storage to populate Torus storage pool (with the host volume).

```YAML
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
          value: 10.3.0.100                         #-> Etcd service clusterIP
        - name: STORAGE_SIZE
          value: 5GiB                               #-> Storage pool maximum size
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
            path: /srv/torus                        #-> HostPath with torus block device
```
```Bash
kubectl create -f etcdv3-daemonset.yml

kubectl get pods --selector="daemon=torus"
NAME          READY     STATUS    RESTARTS   AGE
torus-56p79   1/1       Running   0          1m
torus-87f9t   1/1       Running   0          1m
torus-wc54r   1/1       Running   0          1m
```

On a machine running Kubectl, we can control Torus cluster with the binaries we saw previously. To do so we use the port forward feature of Kubectl to access an etcd pod :

```Bash
kubectl port-forward etcdv3-4jncl
```

That makes it possible to locally control Torus cluster :

```Bash
torusctl list-peers
Handling connection for 2379
ADDRESS                 UUID                                  SIZE     USED  MEMBER  UPDATED        REB/REP DATA
http://10.2.55.2:40000  dce8cf72-45f5-11e6-9426-02420a023702  5.0 GiB  0 B   OK      4 seconds ago  0 B/sec
http://10.2.78.3:40000  dd53432a-45f5-11e6-8fec-02420a024e03  5.0 GiB  0 B   OK      4 seconds ago  0 B/sec
http://10.2.36.4:40000  dd800d8c-45f5-11e6-b812-02420a022404  5.0 GiB  0 B   OK      2 seconds ago  0 B/sec
Balanced: true Usage:  0.00%
```

So in our case, we have 3 instances with each a 5GiB pool, like we specified into Torus' manifest. We create a 1GiB volume for our etherpad app :

```Bash
torusctl volume create-block pad 1GiB
torusctl volume list
Handling connection for 2379
VOLUME NAME  SIZE     TYPE
pad          1.0 GiB  block
```

The volume `pad` is now available has a Kubernetes volume.

## Etherpad deployment

Like the other, etherpad is deploy on top of Kubernetes with a `deployment` and a `service` :

```YAML
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
            driver: "coreos.com/torus"              #-> FlexVolume driver
            fsType: "ext4"
            options:
              volume: "pad"                         #-> Name of the previously created Torus volume
              etcd: "10.3.0.100:2379"               #-> Etcd service clusterIP
```

To check the deployment :

```Bash
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

To simplify the demo, etherpad service is published on a NodePort, it means that we can join the service on every node at port 31594.

To verify data persistence we are going to create a pad named "Torus" :

<center><img src="/images/etherpad-pod1.png" alt="etherpad-pod1" width="500" align="middle"></center>

To test, we are going to label a node as unschedulable (*cordon* in Kubernetes language), then destroy the etherpad pod that will be automatically reschedule on another node :

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

Scheduling is disable on node 192.168.122.111. Let's detroy etherpad pod :

```Bash
kubectl get pods --selector="app=etherpad"
NAME                        READY     STATUS    RESTARTS   AGE
etherpad-2266423034-6wk4u   1/1       Running   0          14m

kubectl delete pods etherpad-2266423034-6wk4u
pod "etherpad-2266423034-6wk4u" deleted
```

Check the new pod :

```Bash
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

Ok, it is just screen capture so I invite you to trust me on this one or test by yourself :)

# Conclusion

Torus is a young product that fits right into the philosophy behind other OSS products launched by CoreOS.

Even if block storage has little interest on a Kubernetes supported cloud provider (Kubernetes already supports PD on GCE, EBS on AWS, Cinder on OpenStack), if you are running on premises or on an unspported cloud provider, Torus can be used to aggregate the storage of multiple instances at no cost.

Finally, about GlusterFS and/or NFS, Torus is not at the same level as only block storage is available for now.

Let's see how the product is going to evolve and also if it will be meeting the same kind of enthusiasm as other CoreOS products.

**Kevin Lefevre**
