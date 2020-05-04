---
Title: Un cluster Kubernetes avec Terraform, Scaleway Kapsule et des GPU
Date: 2020-04-23
Category: Kubernetes
Summary: Déploiement d'un cluster Kubernetes avec Terraform, Scaleway Kapsule et exploitation des GPU Scaleway pour une application de détection de visages
Author: Romain Guichard
image: images/thumbnails/logo-scaleway-elements.png
lang: fr
---

On peut distinguer deux types de clusters Kubernetes, ceux qui sont managés et
ceux qui ne le sont pas. Un Kubernetes managé est un cluster Kubernetes dont
vous ne gérez pas le control plane. Généralement via une interface web ou une
API, vous pouvez demander la création d'un cluster Kubernetes. On considère que
le control plane est managé car vous n'aurez pas à faire les updates vous
même, la supervision est souvent déjà configurée etc. Les workers peuveut être
parfois managés, c'est le cas notamment avec le combo [EKS/Fargate associé par
Virtual Kubelet donc nous avons parlé sur ce
blog](https://particule.io/en/blog/virtual-kubelet/), mais généralement ils
sont à votre charge.

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
- [Kapsule](https://www.scaleway.com/fr/kubernetes-kapsule/) chez Scaleway

Toutes ces solutions ont en commun d'être [certifiées conformes par la
CNCF](https://www.cncf.io/certification/software-conformance/).

![kubernetes certified](/images/certified_kubernetes_color-222x300.png)

Et c'est sur cette dernière que nous allons nous arrêter.

Pourquoi celle ci ? Tout d'abord car c'est une des dernières sortie et que
comme la solution des trois "gros" (AWS, GCP, Azure), des [ressources Terraform
sont disponibles](https://www.terraform.io/docs/providers/scaleway/index.html)
afin de déployer un cluster Kubernetes (mais pas que !) entièrement **as
code**.

[Et c'est quelque chose d'extrêmement important pour
nous.](https://particule.io/#about)


# Déploiement de Kapsule

Il nous faut tout d'abord récupérer notre Access Key et notre Secret Key pour
pouvoir connecter Terraform à l'API de Scaleway. Cela se passe dans la partie
"Credentials" de votre compte.

![scaleway token](/images/kapsule/token.png)

Générez un nouveau token et vous obtiendrez votre Access Key et Secret Key.

Je vous propose de les stocker dans un fichier `credentials.rc` que nous
sourcerons. L'ORGANIZATION_ID se trouve sur la même page.

```bash
export SCW_ACCESS_KEY="monacceskey"
export SCW_SECRET_KEY="masecretkey"
export SCW_DEFAULT_ORGANIZATION_ID="organizationid"
```

Avec Terraform on va déployer seulement un cluster Kubernetes pour le moment.

```terraform
provider "scaleway" {
  zone            = "fr-par-1"
  region          = "fr-par"
}

resource "scaleway_k8s_cluster_beta" "particule" {
  name = "particule"
  version = "1.18.2"
  cni = "weave"
  enable_dashboard = false
  ingress = "nginx"
  default_pool {
    node_type = "GP1-XS"
    size = 1
    autoscaling = true
    autohealing = true
    min_size = 1
    max_size = 3
  }
}

resource "local_file" "kubeconfig" {
  content = scaleway_k8s_cluster_beta.particule.kubeconfig[0].config_file
  filename = "${path.module}/kubeconfig"
}

output "cluster_url" {
  value = scaleway_k8s_cluster_beta.particule.apiserver_url
}
```

On configure le provider avec la `zone` et la `region`.

Pour le cluster, on prend des valeurs plutôt classiques. Il est extrêmement
intéressant de noter que contrairement à **toutes** les autres solutions
Kubernetes managées que j'ai citées en début d'article, Kapsule propose la toute
dernière version de Kubernetes, la `1.18.2` sortie il y a seulement quelques
jours à l'heure où j'écris ces lignes. C'est peut être un détail pour vous,
mais pour nous ça veut dire beaucoup ;-)

Kapsule nous permet aussi de choisir certains addons, on s'orientera donc sur
Weave pour le réseau (Calico est aussi disponible) et sur nginx comme Ingress
Controller (Traefik est aussi disponible).

Kapsule prend directement la fonction de cluster autoscaler en charge et peut faire
grossir notre pool en fonction de la charge. C'est un comportement de base
qu'on devrait retrouver partout de nos jours, cela fait plaisir de l'avoir ici.

Afin de récupérer le kubeconfig généré, on se propose de l'enregistrer dans un
fichier dans notre répertoire courant avec la ressource `local_file`.

Et on lance tout ça :

```console
$ source credentials.rc
$ terraform init

Initializing the backend...

Initializing provider plugins...

[ ... ]

* provider.local: version = "~> 1.4"
* provider.scaleway: version = "~> 1.14"

Terraform has been successfully initialized!

$ terraform apply

[ ... ]

scaleway_k8s_cluster_beta.particule: Creation complete after 47s [id=fr-par/09ddf5f2-a6e5-4785-8d50-8f343e8cad25]
local_file.kubeconfig: Creation complete after 0s [id=c423d6c824739d0f75416a3465919f303ba00856]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

cluster_url = https://09ddf5f2-a6e5-4785-8d50-8f343e8cad25.api.k8s.fr-par.scw.cloud:6443
```

Première impression, c'est plutôt rapide.

Attention, le control plane est peut etre UP mais votre worker pas encore. Il
faut attendre une petite minute avant de pouvoir fièrement lancer :

```console
$ export KUBECONFIG=$PWD/kubeconfig
$ kubectl get node -o wide
NAME                                             STATUS   ROLES    AGE    VERSION   INTERNAL-IP     EXTERNAL-IP    OS-IMAGE                        KERNEL-VERSION     CONTAINER-RUNTIME
scw-particule-default-acad9e189f854d85bb4314ae   Ready    <none>   139m   v1.18.2   10.12.140.221   51.15.139.93   Ubuntu 18.04.3 LTS 0e02a62fb5   5.3.0-42-generic   docker://19.3.5
```

# Test d'une application Hello World

On peut maintenant tester une application, on va utiliser [un bête HelloWorld
sur une page
web](https://github.com/particuleio/helloworld/tree/master/deploy/kubernetes).
Oui on utilise toujours la même, on prend peu de risque.

```console
$ kubectl apply -f https://raw.githubusercontent.com/particuleio/helloworld/master/deploy/kubernetes/service.yaml
$ kubectl apply -f https://raw.githubusercontent.com/particuleio/helloworld/master/deploy/kubernetes/deployment.yaml
$ kubectl get pod,svc
NAME                              READY   STATUS    RESTARTS   AGE
pod/helloworld-67d678b5cd-d2b64   1/1     Running   0          60s

NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
service/helloworld   NodePort    10.38.244.209   <none>        80:31920/TCP   154m
```

Le Service est de type NodePort, on peut donc effectuer un curl sur l'IP
externe de notre noeud et le NodePort du Service.

```console
$ curl 51.15.139.93:31920
<html>
<head>
	<title>Hello world!</title>

[ ... ]

	<h3>My hostname is helloworld-67d678b5cd-d2b64</h3>			<h3>Links found</h3>
					<b>HELLOWORLD</b> listening in 80 available at tcp://10.38.244.209:80<br />
						<b>KUBERNETES</b> listening in 443 available at tcp://10.32.0.1:443<br />
				</body>
</html>
```

Notre application répond tout va bien !


# Corsons le jeu avec des GPU

[La feature intéressante chez Kapsule est la disponibilité des GPU au sein de
Kubernetes. Les GPU sont des Nvidia
P100](https://www.scaleway.com/fr/gpu-instances/).

On va déployer un nouveau pool de worker, cette fois des workers qui possèdent
des GPU, et on va l'ajouter à notre cluster existant. On ajoute ce code
Terraform.

```
resource "scaleway_k8s_pool_beta" "pool_gpu" {
  cluster_id = scaleway_k8s_cluster_beta.particule.id
  name = "gpu"
  node_type = "RENDER-S"
  size = 1
  min_size = 1
  max_size = 1
  autoscaling = true
  autohealing = true
  container_runtime = "docker"
}
```

`RENDER-S` est le gabarit à utiliser pour obtenir un node avec GPU.

```console
terraform apply
scaleway_k8s_cluster_beta.particule: Refreshing state... [id=fr-par/09ddf5f2-a6e5-4785-8d50-8f343e8cad25]
local_file.kubeconfig: Refreshing state... [id=c423d6c824739d0f75416a3465919f303ba00856]

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # scaleway_k8s_pool_beta.pool_gpu will be created
  + resource "scaleway_k8s_pool_beta" "pool_gpu" {
      + autohealing         = true
      + autoscaling         = true
      + cluster_id          = "fr-par/09ddf5f2-a6e5-4785-8d50-8f343e8cad25"
      + container_runtime   = "docker"
      + created_at          = (known after apply)
      + id                  = (known after apply)
      + max_size            = 1
      + min_size            = 1
      + name                = "gpu"
      + node_type           = "RENDER-S"
      + nodes               = (known after apply)
      + region              = (known after apply)
      + size                = 1
      + status              = (known after apply)
      + updated_at          = (known after apply)
      + version             = (known after apply)
      + wait_for_pool_ready = false
    }

Plan: 1 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

scaleway_k8s_pool_beta.pool_gpu: Creating...
scaleway_k8s_pool_beta.pool_gpu: Creation complete after 2s [id=fr-par/5171c26e-c200-4404-93f1-22e1be30beef]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

cluster_url = https://09ddf5f2-a6e5-4785-8d50-8f343e8cad25.api.k8s.fr-par.scw.cloud:6443

$ kubectl get node -o wide
NAME                                             STATUS   ROLES    AGE    VERSION   INTERNAL-IP     EXTERNAL-IP    OS-IMAGE                        KERNEL-VERSION     CONTAINER-RUNTIME
scw-particule-default-acad9e189f854d85bb4314ae   Ready    <none>   3h9m   v1.18.2   10.12.140.221   51.15.139.93   Ubuntu 18.04.3 LTS 0e02a62fb5   5.3.0-42-generic   docker://19.3.5
scw-particule-gpu-f43a7f554e7a4a50838c3a8e445c   Ready    <none>   69m    v1.18.2   10.1.145.35     51.158.69.50   Ubuntu 18.04.3 LTS 0e02a62fb5   5.3.0-26-generic   docker://19.3.1
```

Notre node est déployé.

Nous allons tout d'abord vérifier si nous avons bel et bien un GPU sur ce
worker. Tout d'abord il faut qu'une ressource de type `nvidia.com/gpu` existe
sur notre noeud et il faut que celle ci soit exposée dans notre pod.

Voici un pod de test pour monter un GPU :

```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: pod-gpu
spec:
  restartPolicy: OnFailure
  containers:
    - name: cuda-container
      image: k8s.gcr.io/cuda-vector-add:v0.1
      command:
      - /bin/bash
      - -c
      - sleep 500
      resources:
        limits:
          nvidia.com/gpu: 1
```

```console
$ kubectl apply -f pod-gpu.yaml
pod/pod-gpu created

$ kubectl exec -it pod-gpu -- /bin/bash
root@pod-gpu:/usr/local/cuda-8.0/samples/0_Simple/vectorAdd# nvidia-smi
Thu Apr 23 17:38:44 2020
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 440.33.01    Driver Version: 440.33.01    CUDA Version: 10.2     |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
|===============================+======================+======================|
|   0  Tesla P100-PCIE...  Off  | 00000000:00:03.0 Off |                    0 |
| N/A   28C    P0    26W / 250W |      0MiB / 16280MiB |      0%      Default |
+-------------------------------+----------------------+----------------------+

+-----------------------------------------------------------------------------+
| Processes:                                                       GPU Memory |
|  GPU       PID   Type   Process name                             Usage      |
|=============================================================================|
|  No running processes found                                                 |
+-----------------------------------------------------------------------------+

$ kubectl describe node scw-particule-gpu-f43a7f554e7a4a50838c3a8e445c
Name:               scw-particule-gpu-f43a7f554e7a4a50838c3a8e445c
[...]
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests   Limits
  --------           --------   ------
  cpu                40m (0%)   200m (2%)
  memory             20Mi (0%)  100Mi (0%)
  ephemeral-storage  0 (0%)     0 (0%)
  hugepages-1Gi      0 (0%)     0 (0%)
  hugepages-2Mi      0 (0%)     0 (0%)
  nvidia.com/gpu     1          1
Events:              <none>

```

Tout a l'air en ordre ! On voit bien notre carte `Tesla P100` à l'intérieur de
notre pod.

Essayons de l'utiliser maintenant.

# Face recognition

Tout d'abord, disclaimer. Je ne comprends rien à tout ce qui est IA, Machine
learning, Deep learning, réseaux de neurones etc. Tout ce qui va suivre n'est
qu'une récupération simplissime de ce que certains de mes collègues savent
faire avec des GPU sur Kubernetes.

Scaleway a [un très bel article sur un exemple d'utilisation des
GPU](https://blog.scaleway.com/2019/gpu-instances-using-deep-learning-to-obtain-frontal-rendering-of-facial-images/), bien plus
complet, juste et précis que ce que je vais m'appréter à écrire.

Allez on y va !

Voici le pod que nous allons utiliser. Le Dockerfile de l'image se trouve
[ici](https://github.com/particuleio/facerecognition).

```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: facerecognition
spec:
  containers:
  - name: facerecognition
    image: particule/facerecognition
    command: ["/bin/sh"]
    args: ["-c", "while true; do echo hello; sleep 10;done"]
    resources:
      limits:
         nvidia.com/gpu: 1
```

Copions la vidéo dans le pod et connectons nous au pod pour lancer le script de
détection de visage

```console
$ wget https://raw.githubusercontent.com/ageitgey/face_recognition/master/examples/short_hamilton_clip.mp4
$ kubectl cp short_hamilton_clip.mp4 facerecognition:/tmp
$ kubectl exec -it facerecognition -- /bin/bash
root@facerecognition:/# cd /tmp
root@facerecognition:/tmp# ls
find_faces_in_batches.py  short_hamilton_clip.mp4
root@facerecognition:/tmp# python3 ./find_faces_in_batches.py
I found 0 face(s) in frame #0.
I found 0 face(s) in frame #1.
I found 0 face(s) in frame #2.

[ ... ]

 - A face is located at pixel location Top: 92, Left: 148, Bottom: 171, Right: 227
 - A face is located at pixel location Top: 100, Left: 372, Bottom: 179, Right: 451
 - A face is located at pixel location Top: 60, Left: 36, Bottom: 139, Right: 115
I found 4 face(s) in frame #235.
 - A face is located at pixel location Top: 50, Left: 302, Bottom: 145, Right: 397
 - A face is located at pixel location Top: 92, Left: 148, Bottom: 171, Right: 227
 - A face is located at pixel location Top: 60, Left: 36, Bottom: 139, Right: 115
 - A face is located at pixel location Top: 100, Left: 372, Bottom: 179, Right: 451
I found 4 face(s) in frame #240.
 - A face is located at pixel location Top: 50, Left: 302, Bottom: 145, Right: 397
 - A face is located at pixel location Top: 100, Left: 380, Bottom: 179, Right: 459
 - A face is located at pixel location Top: 92, Left: 156, Bottom: 171, Right: 235
 - A face is located at pixel location Top: 52, Left: 36, Bottom: 131, Right: 115
```

Et voilà !!


# Conclusion

Kubernetes Kapsule de Scaleway est un Kubernetes managé, comme EKS, GKE ou AKS.
Celui ci a la particularité d'être managé par une entreprise française. Son
prix est virtuellement gratuit, vous ne payez en effet que les ressources
associées à vos workers. Comme tout service managé, vous ne payez pas les ressources
associées au control plane.  C'est une vieille promesse du cloud computing :
*pay as you go*. Et enfin il a le mérite de bénéficier de ressources Terraform
ce qui n'est pas si commun lorsqu'on sort du Big Three et méritait d'être
signalé. Ces ressources Terraform nous permettent de piloter notre cluster de
façon déclarative grâce à **l'Infra as Code**.


Nous ne sommes pas rentrés dans tous les détails de Kapsule, mais sachez que le
type `LoadBalancer` pour les Services Kubernetes est disponible et permet de
schéduler automatiquement un Load Balancer sur l'infrastructure de Scaleway.
Exactement comme avec un ELB/ALB sur Amazon Web Services. Une `StorageClass` en
RWO est aussi disponible pour y stocker vos données persistantes.

Tous ces éléments font de Kubernetes Kapsule un produit complet, efficace qui
mérite d'être pleinement considéré lorsque l'on souhaite choisir le cloud
public où déployer son cluster Kubernetes. Enfin les GPU que nous avons
brievement mis en action dans cet article ne coûtent que 1€/heure ;-)


[**Romain Guichard**](https://www.linkedin.com/in/romainguichard)
