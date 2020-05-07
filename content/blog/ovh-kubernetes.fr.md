---
Title: Managed OVH Kubernetes 
Date: 2020-05-07
Category: Kubernetes
Summary: On a testé le Kubernetes Managé d'OVH
Author: Kevin Lefevre
image: images/thumbnails/kubernetes.png
imgSocialNetwork: images/og/kapsule.png
lang: fr
---

On peut distinguer deux types de clusters Kubernetes, ceux qui sont managés et
ceux qui ne le sont pas. Un Kubernetes managé est un cluster Kubernetes dont
vous ne gérez pas le control plane. Généralement via une interface web ou une
API, vous pouvez demander la création d'un cluster Kubernetes. On considère que
le control plane est managé car vous n'aurez pas à faire les updates vous
même, la supervision est souvent déjà configurée etc. Les workers peuvent être
parfois managés, c'est le cas notamment avec [les managed node groups sur
EKS](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html)
ou [les node pools sur
GKE](https://cloud.google.com/kubernetes-engine/docs/concepts/node-pools).

Les workers peuvent parfois être serverless, par exemple avec [EKS/Fargate
associé par Virtual Kubelet dont nous avons parlé sur ce
blog](https://particule.io/en/blog/virtual-kubelet/)

Dans les deux cas, les ressources de calcul sont généralement à votre charge.

La quasi totalité des cloud public providers fournissent une solution managée
de Kubernetes :

- [Elastic Kubernetes Engine (EKS)](https://aws.amazon.com/fr/eks/) pour Amazon Web Services
- [Google Kubernetes Engine
  (GKE)](https://cloud.google.com/kubernetes-engine?hl=fr) pour Google
- [Azure Kubernetes Service (AKS)](https://azure.microsoft.com/fr-fr/services/kubernetes-service/) pour Microsoft Azure
- [Managed Kubernetes
  Service](https://www.ovhcloud.com/fr/public-cloud/kubernetes/) pour OVH
- [Managed Kubernetes](https://www.digitalocean.com/products/kubernetes/) chez
  DigitalOcean
- [Kubernetes Kapsule](https://www.scaleway.com/fr/kubernetes-kapsule/) chez Scaleway

Toutes ces solutions ont en commun d'être [certifiées conformes par la
CNCF](https://www.cncf.io/certification/software-conformance/).

![kubernetes certified](/images/certified_kubernetes_color-222x300.png#center)

Après [avoir testé](https://particule.io/blog/scaleway-kapsule/) la solution
[Kapsule de
Scaleway](https://www.scaleway.com/en/docs/get-started-with-scaleway-kubernetes-kapsule/),
nous allons aujourd'hui tester le [Kubernetes managé
d'OVH](https://docs.ovh.com/gb/en/kubernetes/).

### Déploiement d'OVH Kubernetes

Il est possible dans un premier temps d'accéder au service Kubernetes managé
depuis votre console [OVH public
Cloud](https://www.ovh.com/manager/public-cloud).

![](/images/ovh/ovh-kubernetes-01.png#center)

Il est ensuite possible de sélectionner la région ainsi que la version du
cluster. Les version proposées vont de 1.15 à 1.17. Nous allons de déployer un
cluster en 1.17.

![](/images/ovh/ovh-kubernetes-02.png#center)

![](/images/ovh/ovh-kubernetes-03.png#center)

Le cluster est disponible en 5 minutes, il est temps d'ajouter des nœuds. La
console OVH propose une interface pour gérer le cluster et les nœuds. Les nœuds
disponibles sont les même instances que celles proposées par le public cloud
OVH. Pour le moment les nœuds sont rajouté de manière individuel mais le concept
de node pool et d'autoscaling sera [disponible cette
année](https://docs.ovh.com/sg/en/kubernetes/available-upcoming-features/).

Pour le moment, pas de GPU avec Kubernetes mais un [OVH lab est en cours
d'élaboration](https://labs.ovh.com/gpu-baremetal-kubernetes-nodes)qui permettra
d'ajouter des nœuds bare metal avec des GPUs.

Rajouter des nœuds se fait simplement dans l'interface:

![](/images/ovh/ovh-kubernetes-04.png#center)

### Récupération du Kubeconfig

Le Kubeconfig est téléchargeable également depuis l'interface. Il est ensuite possible d'accéder au cluster:

```bash
export KUBECONFIG=$(pwd)/kubeconfig.yml

kubectl get nodes -o wide

NAME          STATUS   ROLES    AGE    VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
particule     Ready    <none>   17m    v1.17.5   51.210.39.198   <none>        Ubuntu 18.04.4 LTS   4.15.0-96-generic   docker://18.6.3
particule-b   Ready    <none>   109s   v1.17.5   51.210.36.244   <none>        Ubuntu 18.04.4 LTS   4.15.0-96-generic   docker://18.6.3

kubectl get pods -o wide --all-namespaces

NAMESPACE     NAME                                   READY   STATUS    RESTARTS   AGE     IP              NODE          NOMINATED NODE   READINESS GATES
kube-system   canal-br6v7                            2/2     Running   0          2m21s   51.210.36.244   particule-b   <none>           <none>
kube-system   canal-zrl4j                            2/2     Running   0          17m     51.210.39.198   particule     <none>           <none>
kube-system   coredns-76bd8dbd8c-gm9bk               1/1     Running   0          2m11s   10.2.0.5        particule     <none>           <none>
kube-system   coredns-76bd8dbd8c-hg49c               1/1     Running   0          32m     10.2.0.2        particule     <none>           <none>
kube-system   kube-dns-autoscaler-64bc6d94b9-79x2z   1/1     Running   0          32m     10.2.0.3        particule     <none>           <none>
kube-system   kube-proxy-rmglz                       1/1     Running   0          17m     51.210.39.198   particule     <none>           <none>
kube-system   kube-proxy-tr8s9                       1/1     Running   0          2m21s   51.210.36.244   particule-b   <none>           <none>
kube-system   metrics-server-857c75cd6f-7mxx6        1/1     Running   0          31m     10.2.0.4        particule     <none>           <none>
kube-system   wormhole-4dztq                         1/1     Running   0          2m21s   51.210.36.244   particule-b   <none>           <none>
kube-system   wormhole-pvzjf                         1/1     Running   0          17m     51.210.39.198   particule     <none>           <none>
```

La solution de CNI utilisée est
[canal](https://docs.projectcalico.org/getting-started/kubernetes/flannel/flannel),
qui combine
[flannel](https://coreos.com/flannel/docs/latest/flannel-config.html) et
[calico](https://docs.projectcalico.org/getting-started/kubernetes/) pour les
[network
policy](https://kubernetes.io/docs/concepts/services-networking/network-policies/). 

Pour l'instant le trafic transit sur le réseau publi d'OVH et est chiffré via la
solution CNI [wormhole](https://github.com/gravitational/wormhole).
L'integration au vRack et la possibilité de créer des cluster privés sera
[ajoutée dans
l'année](https://docs.ovh.com/sg/en/kubernetes/available-upcoming-features/).

#### Comment automatiser ?

OVH dispose d'un [provider
Terraform](https://www.terraform.io/docs/providers/ovh/index.html),
malheureusement la ressource Kubernetes n'est pas disponible pour le moment mais
on nous dit dans l'oreillette que ca ne saurait tarder.

Il est tout de même possible de déployer via
[l'API](https://docs.ovh.com/gb/en/customer/first-steps-with-ovh-api/), cette
API est également accessible via une [WebUI](https://api.ovh.com/console) qui
propose de piloter les différents services offert par OVH.

### Fonctionnalités disponibles

Parmi les fonctionnalités exposées, on notera l'intégration au stockage
persistant Cinder pour les workload stateful (support du redimensionnement), la gestion de
l'autoscaling des pods via
[HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
ainsi que l'intégration des loadbalancer.

Une liste des différentes fonctionnalités est [disponible
ici](https://docs.ovh.com/gb/en/kubernetes/).

#### Mini demo

Pour tester les load balancer et les volumes cinder, vous pouvez utiliser ce
`yaml`:

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-world
  labels:
    app: hello-world
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello-world
  template:
    metadata:
      labels:
        app: hello-world
    spec:
      containers:
      - name: hello-world
        image: particule/helloworld:latest
        ports:
        - containerPort: 80
        volumeMounts:
        - mountPath: "/claim"
          name: pv-storage
      volumes:
      - name: pv-storage
        persistentVolumeClaim:
          claimName: pv-claim
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: hello-world
  name: hello-world
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
  selector:
    app: hello-world
  type: LoadBalancer
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pv-claim
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi

```

Puis:

```
k apply -f ovh.yaml
deployment.apps/hello-world created
service/hello-world created
persistentvolumeclaim/pv-claim created
```

Après quelques minutes, les ressources sont disponibles.

```bash
kubectl get pods

NAME                           READY   STATUS    RESTARTS   AGE
hello-world-6cf5f597cb-6jvrj   1/1     Running   0          5m19s

kubectl get pv

NAME                                                                     CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM              STORAGECLASS            REASON   AGE
ovh-managed-kubernetes-rq4ajb-pvc-aa2e0e0c-d44b-4210-89f0-293f6ed7f94a   10Gi       RWO            Delete           Bound    default/pv-claim   csi-cinder-high-speed            10m

kubectl get pvc

NAME       STATUS   VOLUME                                                                   CAPACITY   ACCESS MODES   STORAGECLASS            AGE
pv-claim   Bound    ovh-managed-kubernetes-rq4ajb-pvc-aa2e0e0c-d44b-4210-89f0-293f6ed7f94a   10Gi       RWO            csi-cinder-high-speed   10m

kuebctl get svc

NAME          TYPE           CLUSTER-IP   EXTERNAL-IP                         PORT(S)        AGE
hello-world   LoadBalancer   10.3.46.3    6epat74kjk.lb.c1.gra7.k8s.ovh.net   80:32063/TCP   8m3s
```

Notre service est accessible sur l'url <http://6epat74kjk.lb.c1.gra7.k8s.ovh.net>

![](/images/ovh/ovh-kubernetes-05.png#center)

On peut également voir dans le pod notre volume persistant monté dans `/claim`.

```bash
k exec -it hello-world-6cf5f597cb-6jvrj -- /bin/sh

df -h

Filesystem                Size      Used Available Use% Mounted on
/dev/sdb                  9.8G     36.0M      9.7G   0% /claim
```

### Fonctionnalité prévues

Nous les avons mentionnées en cours d'article mais un petit récapitulatif ne
fait pas de mal:

* Intégration au vRack pour les clusters et réseaux privés.
* Autoscaling des nœuds via la fonction de node groups
* Nœuds baremetal et GPU.

### Conclusion

Le service reste pour le moment un peu limité en terme de fonctionnalités mais
une fois intégré avec le catalogue de services OVH et notamment le vRack, les
possibilités d'intégration seront fortement étendues. Pour nous, intégrer ce
service aux modules Terraform est également un "must have".
