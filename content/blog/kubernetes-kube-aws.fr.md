---
lang: fr
Title: Déployer un cluster Kubernetes sur AWS avec kube-aws
Date: 2016-05-13
Category: Kubernetes
Series:  Kubernetes deep dive
Summary: Premier article de la série sur Kubernetes, on commence avec le déploiement d'un cluster sur AWS "the CoreOS way"
Author: Kevin Lefevre
image: images/thumbnails/kubernetes.png
---

<center><img src="/images/docker/kubernetes.png" alt="coreos" width="400" align="middle"></center>

Particule vous propose un dossier sur Kubernetes. Nous allons dans ce premier article déployer un cluster Kubernetes sur AWS, puis tester son fonctionnement de base - en particulier les fonctionnalités liées au Cloud Provider. Le but n'est pas d'installer à la main Kubernetes étape par étape mais de montrer une méthode de déploiement, sur un Cloud Provider que nous utilisons : Amazon Web Services.

# Le Choix de CoreOS pour Kubernetes

Kubernetes est un projet Open Source lancé en 2014 par Google. Popularisé en quelques années seulement, ce COE (*Container Orchestration Engine*) permet de gérer le cycle de vie d'applications de type [12 factor](http://12factor.net/) / micro-services à l'aide de conteneurs. Kubernetes propose des fonctionnalités de clustering, de déploiement automatique et de scalabilité ainsi que des API ouvertes. Les configurations se font à l'aide de fichiers JSON ou YAML.
À noter que d'autres COE existent, parmi lesquels Docker Swarm et Apache Mesos.

Nous avons fait ici le choix de la distribution Linux CoreOS, une distribution minimaliste orientée conteneurs dont nous avons déjà parlé dans des [précédents](discovery-service-avec-consul.html) [articles](coreos-cluster-et-docker.html). Le projet Open Source "CoreOS" est porté par la société *CoreOS, Inc*, à l'origine de nombre services OpenSource orientés conteneurs tels que :

  * [RKT](https://coreos.com/rkt/) : container engine
  * [Etcd](https://coreos.com/etcd/) : K/V store
  * [Flannel](https://coreos.com/flannel/docs/latest/) : overlay network
  * [Fleet](https://coreos.com/fleet/) : systemd distribué

Membre de l'*Open Container Initiative* (OCI), *CoreOS, Inc* a également compté parmi les premiers à pousser l'utilisation de Kubernetes en production, et propose une solution packagée de Kubernetes appelée Tectonic.
CoreOS est donc une distribution de choix pour faire fonctionner Kubernetes, même sans avoir recours à la version commerciale.

# The "CoreOS way"

Dans le respect des best practices, les fonctionnalités suivantes sont déployées :

- Utilisation de TLS pour sécuriser les communications;
- Utilisation du service de discovery de Kubernetes;
- Utilisation d'un Cloud Provider : AWS.

Kubernetes supporte de multiples Cloud Providers, dont AWS, pour permettre l'utilisation de composants externes mis à disposition. Par exemple, dans le cas de la publication de services, il est possible d'automatiquement provisionner un ELB (*Elastic Load Balancer*) ainsi que les règles de filtrage (security groups) associées.
Nous utiliserons dans cet article un outil de déploiement CoreOS appelé [*kube-aws*](https://coreos.com/kubernetes/docs/latest/kubernetes-on-aws.html), permettant de déployer facilement un cluster dans AWS.

# Préparation du cluster

Pour préparer le cluster, nous allons utiliser [*kube-aws*](https://github.com/coreos/coreos-kubernetes/tree/master/multi-node/aws), un outil qui permet de gérer un cluster Kubernetes en mode Infrastructure as Code. À partir d'un template YAML, *kube-aws* génère un template CloudFormation et le provisionne sur AWS. Les templates générés peuvent par exemple être stockés sur un dépôt Git, comme pour les templates [Terraform](https://www.terraform.io/), afin d'être versionnés.

## Pré-requis

Les objets sont multiples dans Kubernetes :

- Pod : plus petit élement unitaire, peut contenir un ou plusieurs conteneurs fonctionnant ensemble, avec des composants partagés et qui doivent former un composant logique
- Replication Controller : contrôle la durée de vie des pods notamment le nombre de pods dans un cluster à un instant T
- Services : permet de fournir un niveau d'abstraction (point d'entrée unique) aux pods qui peuvent physiquement se trouver sur différents hôtes du cluster et être répliqués par les replication controllers

L'installation et la gestion de Kubernetes nécessitent l'installation de 2 binaires, par exemple sur linux dans `/usr/local/bin` :

- [*kube-aws*](https://github.com/coreos/coreos-kubernetes/releases) : pré-configurer le cluster et le déployer
- kubectl : contrôle de Kubernetes via les API :

```
curl -O https://storage.googleapis.com/kubernetes-release/release/v1.2.3/bin/linux/amd64/kubectl
```

Pour pouvoir se connecter aux instances, si besoin, il est nécessaire de disposer d'une clé SSH sur AWS EC2 ainsi que d'un compte IAM valide afin de pouvoir provisionner l'infrastructure sur AWS. De plus, afin d'assurer la sécurité des communications au sein du cluster ainsi qu'entre les composants d'AWS, *AWS Key Management Service (KMS)* est utilisé. Pour générer une clé via *awscli* :

```
aws --profile particule kms --region=eu-west-1 create-key --description="particule-k8s-clust kms"
{
    "KeyMetadata": {
        "KeyId": "6d9f59dc-e5c1-441d-8743-4d55c7cd1701",
        "KeyState": "Enabled",
        "AWSAccountId": "303293004898",
        "Arn": "arn:aws:kms:eu-west-1:303293004898:key/6d9f59dc-e5c1-441d-8743-4d55c7cd1701",
        "KeyUsage": "ENCRYPT_DECRYPT",
        "Enabled": true,
        "Description": "particule-k8s-clust kms",
        "CreationDate": 1462794561.015
    }
}
```

## Initialisation du cluster

Dans un premier temps, il faut exporter les credentials du compte IAM.

```
$ export AWS_ACCESS_KEY_ID=AKID1234567890
$ export AWS_SECRET_ACCESS_KEY=MY-SECRET-KEY
```

Puis, dans un répertoire dédié, on initialise le cluster.

```
kube-aws init --cluster-name=particule-k8s-clust \
--external-dns-name=k8s.particule.io \
--region=eu-west-1 \
--availability-zone=eu-west-1 \
--key-name=klefevre-sorrow \
--kms-key-arn="arn:aws:kms:eu-west-1:303293004898:key/6d9f59dc-e5c1-441d-8743-4d55c7cd1701" -> Correspond à l'ARN de la clé KMS générée précédemment.
Success! Created cluster.yaml

Next steps:
1. (Optional) Edit cluster.yaml to parameterize the cluster.
2. Use the "kube-aws render" command to render the stack template.
```

Cette commande génère un fichier `cluster.yaml` pré-rempli qui définit les options du cluster. Avant de générer la stack CloudFormation, il est possible de la customiser avec par exemple, le nombre de workers par défaut, la zone DNS Route 53, la taille des instances, etc.

Par exemple, le fichier `cluster.yaml` pour le cluster particule :

```
clusterName: particule-k8s-clust
externalDNSName: k8s.particule.io
releaseChannel: alpha
createRecordSet: true
hostedZone: "particule.io"
keyName: klefevre-sorrow
region: eu-west-1
availabilityZone: eu-west-1a
kmsKeyArn: "arn:aws:kms:eu-west-1:303293004898:key/6d9f59dc-e5c1-441d-8743-4d55c7cd1701"
controllerInstanceType: t2.medium
controllerRootVolumeSize: 30
workerCount: 2
workerInstanceType: t2.small
workerRootVolumeSize: 30
```

Dans cet exemple, le cluster est déployé dans la région `eu-west-1`, dans l'AZ `eu-west-1b`. Nous utilisons des instances `t2.medium` avec des disques de 30Go pour le contrôleur et des instances `t2.small` avec 30 Go de disque pour les nœuds worker. Il y aura au départ 2 workers. Les API seront accessibles à l'adresse `k8s.particule.io` et l'enregistrement DNS sera créé au moment de la création de la stack sur la zone `particule.io` déjà gérée sur AWS Route53.

Ensuite, à partir du fichier `cluster.yaml` on prépare les templates CloudFormation.
```
kube-aws render
Success! Stack rendered to stack-template.json.

Next steps:
1. (Optional) Validate your changes to cluster.yaml with "kube-aws validate"
2. (Optional) Further customize the cluster by modifying stack-template.json or files in ./userdata.
3. Start the cluster with "kube-aws up".
```

Une fois le rendu effectué on se retrouve avec l'arborescence suivante :

```
drwxr-xr-x 4 klefevre klefevre 4.0K May  9 14:57 .
drwxr-xr-x 3 klefevre klefevre 4.0K May  9 11:31 ..
-rw------- 1 klefevre klefevre 3.0K May  9 14:50 cluster.yaml
drwx------ 2 klefevre klefevre 4.0K May  9 14:57 credentials -> contient les ressources pour le TLS
-rw------- 1 klefevre klefevre  540 May  9 14:57 kubeconfig -> fichiers de configuration pour l'utilisation de kubectl
-rw-r--r-- 1 klefevre klefevre  16K May  9 14:57 stack-template.json -> le template CloudFormation géneré
drwxr-xr-x 2 klefevre klefevre 4.0K May  9 14:57 userdata -> contient les fichiers cloud-init pour le master ainsi que les slaves (workers)
```

Pour information, les *userdata* générées avec *kube-aws* sont conformes à la [documentation d'installation manuelle](https://coreos.com/kubernetes/docs/latest/getting-started.html).

Enfin on valide les userdata ainsi que la stack CloudFormation :

```
kube-aws validate
Validating UserData...
UserData is valid.

Validating stack template...
Validation Report: {
  Capabilities: ["CAPABILITY_IAM"],
  CapabilitiesReason: "The following resource(s) require capabilities: [AWS::IAM::InstanceProfile, AWS::IAM::Role]",
  Description: "kube-aws Kubernetes cluster particule-k8s-clust"
}
stack template is valid.

Validation OK!
```

# Déploiement du cluster

Une fois toutes les étapes effectuées, on déploie le cluster avec la simple commande `kube-aws up`.

```
kube-aws up
Creating AWS resources. This should take around 5 minutes.
Success! Your AWS resources have been created:
Cluster Name:   particule-k8s-clust
Controller IP:  52.18.58.120

The containers that power your cluster are now being dowloaded.

You should be able to access the Kubernetes API once the containers finish downloading.
```

Afin de valider le bon fonctionnement du cluster, on peut par exemple lister les nœuds du cluster :

```
kubectl --kubeconfig=kubeconfig get nodes
NAME                                       STATUS    AGE
ip-10-0-0-148.eu-west-1.compute.internal   Ready     4m
ip-10-0-0-149.eu-west-1.compute.internal   Ready     3m
```

Le fichier `kubeconfig` contient les credentials ainsi que les certificats TLS pour accéder aux API de Kubernetes :

```
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority: credentials/ca.pem
    server: https://k8s.particule.io
  name: kube-aws-particule-k8s-clust-cluster
contexts:
- context:
    cluster: kube-aws-particule-k8s-clust-cluster
    namespace: default
    user: kube-aws-particule-k8s-clust-admin
  name: kube-aws-particule-k8s-clust-context
users:
- name: kube-aws-particule-k8s-clust-admin
  user:
    client-certificate: credentials/admin.pem
    client-key: credentials/admin-key.pem
current-context: kube-aws-particule-k8s-clust-context
```

L'enregistrement DNS a automatiquement été créé sur Route53, et l'on remarque bien que la connexion aux API s'effectue via HTTPS.

# Test d'un simple service

Nous allons tester simplement le fonctionnement du cluster pour terminer cet article. Avec par exemple, un serveur Minecraft, publié automatiquement via un ELB.

Dans un premier temps, on définit le *replication controller* `deployment-minecraft.yaml`.

```
apiVersion: v1
kind: ReplicationController
metadata:
  name: minecraft
spec:
  replicas: 1
  selector:
    app: minecraft
  template:
    metadata:
      name: minecraft
      labels:
        app: minecraft
    spec:
      containers:
      - name: minecraft
        image: vsense/minecraft
        ports:
        - containerPort: 25565
```

Dans ce cas, nous avons un seul réplica. Ce qui signifie un seul pod Minecraft. La sélection se fait grâce au label, qui permet au replication controller de matcher le pod avec le même label (ici *minecraft*). On vérifie avec kubectl :

```
kubectl --kubeconfig=kubeconfig create -f deployment-minecraft.yaml
replicationcontroller "minecraft" created

kubectl --kubeconfig=kubeconfig get rc
NAME        DESIRED   CURRENT   AGE
minecraft   1         1         1m

kubeectl --kubeconfig=kubeconfig get pods
NAME              READY     STATUS    RESTARTS   AGE
minecraft-wj65z   1/1       Running   0          1m
```

Pour le moment, le pod est accessible uniquement depuis l'intérieur du cluster, pour le rendre accessible depuis l'extérieur nous allons créer un service au sens Kubernetes et utiliser la fonctionnalité de load balancing fournie par le Cloud Provider. Kubernetes va provisionner un ELB sur AWS, ouvrir les security groups et ajouter les nœuds Kubernetes en backend automatiquement.

Le fichier `service-minecraft.yaml` :

```
apiVersion: v1
kind: Service
metadata:
    name: minecraft
    labels:
        app: minecraft
spec:
    selector:
        app: minecraft
    ports:
        - port: 25565
    type: LoadBalancer
```

Ici, le load balancer écoute sur le même port que le pod (le port 25565, par défaut pour Minecraft) et forward le trafic vers les workers. Pour avoir le détail :

```
kubectl --kubeconfig=kubeconfig create -f service-minecraft.yaml
kubectl --kubeconfig=kubeconfig describe service minecraft
Name:                   minecraft
Namespace:              default
Labels:                 app=minecraft
Selector:               app=minecraft
Type:                   LoadBalancer
IP:                     10.3.0.173
LoadBalancer Ingress:   a3b6af5e415f211e6b97202fce3039af-98360.eu-west-1.elb.amazonaws.com
Port:                   <unset> 25565/TCP
NodePort:               <unset> 31846/TCP
Endpoints:              10.2.92.2:25565
Session Affinity:       None
Events:
  FirstSeen     LastSeen        Count   From                    SubobjectPath   Type            Reason                  Message
  ---------     --------        -----   ----                    -------------   --------        ------                  -------
  41m           41m             1       {service-controller }                   Normal          CreatingLoadBalancer    Creating load balancer
  41m           41m             1       {service-controller }                   Normal          CreatedLoadBalancer     Created load balancer

```

Pour le moment, Kubernetes ne supporte pas la configuration automatique d'un alias Route53 vers le load balancer. Le service est accessible depuis l'extérieur à l'adresse : a3b6af5e415f211e6b97202fce3039af-98360.eu-west-1.elb.amazonaws.com sur le port par défaut (25565), ce qui n'est pas très pratique.

Il est possible d'automatiser la création d'un enregistrement DNS en utilisant la CLI AWS. Dans un fichier `route53-minecraft.json` :

```
{
  "Comment": "minecraft dns record",
  "Changes": [
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "minecraft.particule.io",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [
        {
          "Value": "a3b6af5e415f211e6b97202fce3039af-98360.eu-west-1.elb.amazonaws.com"
        }
        ]
      }
    }
  ]
}
```

Ensuite via l'awscli :

```
aws --profile particule route53 change-resource-record-sets --hosted-zone-id Z2BYZVP5DZBBWK --change-batch file://route53-minecraft.json

host minecraft.particule.io
minecraft.particule.io is an alias for a3b6af5e415f211e6b97202fce3039af-98360.eu-west-1.elb.amazonaws.com.
a3b6af5e415f211e6b97202fce3039af-98360.eu-west-1.elb.amazonaws.com has address 52.17.242.195
a3b6af5e415f211e6b97202fce3039af-98360.eu-west-1.elb.amazonaws.com has address 52.19.180.100
```

Le champs *hosted-zone-id* correspond à l'ID de zone Route53 dans laquelle on ajoute l'enregistrement. On peut ensuite se connecter au service depuis l'extérieur à l'adresse `minecraft.particule.io`.

# Conclusion

Il existe beaucoup de méthodes de déploiement pour Kubernetes, que ce soit via Ansible, Puppet ou Chef. Elles dépendent également du Cloud Provider utilisé. CoreOS est l'une des premières distributions à s'être intégrée avec Kubernetes, et à supporter complètement AWS. Dans une suite d'articles nous nous détacherons de la partie installation et nous nous intéresserons plus précisément au fonctionnement de Kubernetes ainsi qu'aux differents objets disponibles et leurs cas d'utilisation.

**Kevin Lefevre**
