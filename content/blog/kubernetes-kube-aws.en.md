---
Title: Kubernetes on AWS with kube-aws
lang: en
Category: Kubernetes
Date: 2016-05-13
Series: Kubernetes deep dive
Summary: Deploy a Kubernetes cluster on AWS with CoreOS.
Author: Kevin Lefevre
image: images/thumbnails/kubernetes.png
---

<center><img src="/images/docker/kubernetes.png" alt="coreos" width="400" align="middle"></center>

This is the first article of the Kubernetes series. In this article, we are going to deploy a Kubernetes cluster on AWS and test some features - mostly the ones about cloud provider. The goal is not to deploy a cluster manually but to show a deployment method on a cloud provider we are using @Particule : Amazon Web Services

# CoreOS : distribution of choice for Kubernetes

Kubernetes is an Open Source project launched in 2014 by Google. It became popular very quickly. This COE (*Container Orchestration Engine) can manage the life cycle of cloud native / micro services applications ([12 factor](http://12factor.net/) with containers. Kuberntes allows for clustering, automated deployment, horizontal scalability, with opened APIs. Configuration can be written in JSON or YAML.

Other COE exist out there, such as Apache Mesos or Docker Swarm.

We re deploying Kubernetes on CoreOS Linux : a minimalist distribution made for containers. The project is Open Source and originally from the CoreOS company, which also initiated lots of Open Source projets :

  * [RKT](https://coreos.com/rkt/) : container engine
  * [Etcd](https://coreos.com/etcd/) : K/V store
  * [Flannel](https://coreos.com/flannel/docs/latest/) : overlay network
  * [Fleet](https://coreos.com/fleet/) : low level orchestrator (distributed systemd)

Member of the *Open Container Initiative* (OCI), *Core Inc* was among the first to push Kubernetes usage in production, and offers a packaged solution called Tectonic.

CoreOS is also the perfect distribution to run Kubernetes, even without using the commercial version.

# The "CoreOS way"

To respect best practices, the following features are deployed :

  * TLS to secure communication
  * Service Discovery (SkyDNS) for Kubernetes
  * Cloud provider features : AWS

Kuberntes supports multiple cloud prociders which allow the use of external components available in the cloud. For example, to publish services, it is possible to dynamicly provvision an *Elastic Load balancer* (ELB) and associated security rules.

# Cluster bootstrap

To prepare the cluster, we are going to use [*kube-aws*](https://github.com/coreos/coreos-kubernetes/tree/master/multi-node/aws), a tools developed by CoreOS that used CloudFormation stacks to deploy on AWS. From A YAML template, *kube-aws* generates a CloudFormation template and userdate. Generated templates can be stored onto a version control system such as git, like [Terraform](https://www.terraform.io/) templates.

## Prerequisite

There are several objects in Kubernetes :

  * Pod : this is the smallest element, it can include one or more containers that are working together to form a single logical component.
  * Replication Controller : manage the lifecyle of PODs, by ensuring a certain number of PODs is always availabale in the cluster (replicas).
  * Services : abstraction layer between external network and the cluster, it's a unique entry point wichi is then load balance between a set of pods managed by a replication controller.

To install and manage Kubernetes, we need two binaries, you can drop them in `/usr/local/bin` :

  * [*kube-aws*](https://github.com/coreos/coreos-kubernetes/releases) : cluster configuration and bootstrap
  * kubectl : CLI tool to access Kubernetes APIs :

```
curl -O https://storage.googleapis.com/kubernetes-release/release/v1.2.3/bin/linux/amd64/kubectl
```
To be able to connect to EC2 instances, we need on SSH key and a valid IAM account to deploy the infrastrcture on AWS. TO secure communications inside the cluster, we are using *AWS Key Management Services* (KMS).

To generate a Key with *awscli* :

```JSON
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

## Cluster initialization

First we need AWS credentials :

```Bash
$ export AWS_ACCESS_KEY_ID=AKID1234567890
$ export AWS_SECRET_ACCESS_KEY=MY-SECRET-KEY
```

Then in a dedicated directory :

```Bash
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

This command generates a `cluster.yaml` file with some customizable cluster options. Before generating the CloudFormation stack, it is possible de review the file, and change the number of default node, availability zone, route53, instance type, etc. The file is self documented.

`cluster.yaml` file for Particule cluster :

```YAML
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

In this example, we are using the region `eu-west-1` and the AZ `eu-west-1b`. The master is a 30Go `t2.medium` instance and workers are 30Go `t2.small` instances. We are starting with 2 worker nodes. The APIs will be accessible at the address `k8s.particule.io`, a route53 records will be automaticly created on the `particule.io` zone.

Then from this file, we generate the CloudFormation template :

```Bash
kube-aws render
Success! Stack rendered to stack-template.json.

Next steps:
1. (Optional) Validate your changes to cluster.yaml with "kube-aws validate"
2. (Optional) Further customize the cluster by modifying stack-template.json or files in ./userdata.
3. Start the cluster with "kube-aws up".
```

Once the render finishes, we get the following structure :

```Bash
drwxr-xr-x 4 klefevre klefevre 4.0K May  9 14:57 .
drwxr-xr-x 3 klefevre klefevre 4.0K May  9 11:31 ..
-rw------- 1 klefevre klefevre 3.0K May  9 14:50 cluster.yaml
drwx------ 2 klefevre klefevre 4.0K May  9 14:57 credentials -> TLS resources
-rw------- 1 klefevre klefevre  540 May  9 14:57 kubeconfig -> configuration files for kubecetl
-rw-r--r-- 1 klefevre klefevre  16K May  9 14:57 stack-template.json -> generated CloudFormation template
drwxr-xr-x 2 klefevre klefevre 4.0K May  9 14:57 userdata -> userdata (cloud-init) for master and worker nodes
```

Generated userdata are in sync with the [manual installation instructions](https://coreos.com/kubernetes/docs/latest/getting-started.html).

You can edit CloudFormation stack and userdata before validating :

```Bash
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

# Cluster bootstrap

Finally, we can deploy with a simple command `kube-aws up` :

```Bash
kube-aws up
Creating AWS resources. This should take around 5 minutes.
Success! Your AWS resources have been created:
Cluster Name:   particule-k8s-clust
Controller IP:  52.18.58.120

The containers that power your cluster are now being dowloaded.

You should be able to access the Kubernetes API once the containers finish downloading.
```

The stack progression can be monitored on the AWS console, after that, we can check the cluster state :

```Bash
kubectl --kubeconfig=kubeconfig get nodes
NAME                                       STATUS    AGE
ip-10-0-0-148.eu-west-1.compute.internal   Ready     4m
ip-10-0-0-149.eu-west-1.compute.internal   Ready     3m
```


`kubeconfig` file has the credentials and TLS certificates to access the APIs :

```YAML
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

DNS record is automatically created on Route53, and API connections are secured via TLS.

# Simple service demo

To finish this article, we are going to publish a simple service, Minecraft, by using an ELB.

First, we define a *replication controller* : `deployment-minecraft.yaml`.

```Yaml
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

In that case, there is a single replicas, so only one Minecraft pod. A replication controller matches pod via the label directive, it matches pods with the label `app=minecraft`.

```Bash
kubectl --kubeconfig=kubeconfig create -f deployment-minecraft.yaml
replicationcontroller "minecraft" created

kubectl --kubeconfig=kubeconfig get rc
NAME        DESIRED   CURRENT   AGE
minecraft   1         1         1m

kubeectl --kubeconfig=kubeconfig get pods
NAME              READY     STATUS    RESTARTS   AGE
minecraft-wj65z   1/1       Running   0          1m
```

So Minecraft is running, for now the pod is only accessible inside the cluster. To make it accessible outisde the cluster we are going to create a Kubernetes service and use the load balancing feature by the cloud provider. Kubernetes is going to provision an ELB, open security groups and add the worker nodes into the backend pool automatically.

`service-minecraft.yaml` :

```YAML
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

Load balancer is listening on the same port as the pods (port 25565, Minecraft default) and forward traffic to the workers. To get the details :

```Bash
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
For now, Kubernetes does not support the creation of Route53 alias dynamicly. The service is accessible outside at : a3b6af5e415f211e6b97202fce3039af-98360.eu-west-1.elb.amazonaws.com:25565 which is not very practical.

We can create `route53-minecraft.json` :

```Json
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

Then via awscli :

```Bash
aws --profile particule route53 change-resource-record-sets --hosted-zone-id Z2BYZVP5DZBBWK --change-batch file://route53-minecraft.json

host minecraft.particule.io
minecraft.particule.io is an alias for a3b6af5e415f211e6b97202fce3039af-98360.eu-west-1.elb.amazonaws.com.
a3b6af5e415f211e6b97202fce3039af-98360.eu-west-1.elb.amazonaws.com has address 52.17.242.195
a3b6af5e415f211e6b97202fce3039af-98360.eu-west-1.elb.amazonaws.com has address 52.19.180.100
```

*hosted-zone-id* must match ID of the Route53 zone in which we create the records. After that, we can access our services from a friendly URL : `minecraft.particule.io`.

# Conclusion

There are serveral deployment methods for Kubernetes, via Ansible, Puppet, or Chef. They depends on the cloud provider. CoreOS is just one of them and one of the first to have integrated with Kubernetes and supported AWS.

In a next series of articles, we'll move forward installation and focus on running Kubernetes and what the other available features are.

**Kevin Lefevre**
