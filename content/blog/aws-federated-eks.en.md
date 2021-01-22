---
Title: "Create Kubernetes federated clusters on AWS"
Date: 2021-01-21
Category: Amazon Web Services
Summary: Deploy federated Kubernetes Clusters on AWS using their Federated EKS Clusters solution
Author: Theo "Bob" Massard
image: images/thumbnails/eks.png
imgSocialNetwork: images/og/kubefed-eks.png
lang: en
---

AWS recently introduced [their new solution][1] to orchestrate Federated EKS Clusters. The solution
is based on kubefed and deploys an infrastructure with a bastion cluster to operate the clusters
and two EKS clusters in different regions. You can now have highly available EKS setup bootstrapped
using a CloudFormation template in less than an hour.

[1]: https://aws.amazon.com/about-aws/whats-new/2021/01/introducing-federated-amazon-eks-clusters-aws/

### But first, what is kubefed ?

Kubefed (for "Kubernetes Cluster Federation") allows to orchestrate multiple Kubernetes Cluster
by exposing a high-level control pane. Your kubernetes clusters can join the federation cluster
allowing you to create `Federated` CRDs.

Kubefed repository: <https://github.com/kubernetes-sigs/kubefed>

By doing so, you can create [distributed deployments accross multiple clusters][2]
and even share resources such as `ConfigMap` or `Secret`.

[2]: https://github.com/kubernetes-sigs/kubefed/blob/master/docs/userguide.md#replicaschedulingpreference
Using Amazon's Federated EKS, we will setup a kubefedctl bastion and provision two
EKS Clusters using `eksctl` to create a multi-region federated Kubernetes cluster.

![kubefed clusters](/images/kubefed-cluster.png)
_kubefed-based clusters concept_

### what is Federated Amazon EKS ?

The Federated Amazon EKS is a solution aiming to facilitate the deployment of a kubefed-based
multi-cluster infrastructure, using CloudFormation templates. The template provides a way of
creating a bastion host that will act as the kubefed control plane.

This bastion will be bootrstrapped with all the necessary utilities, such as:
- `eksfedctl` for federation administration
- `eksctl` for cluster configuration
- `kubectl` pre-configured to be used in the federation cluster context

Implementation guide: [federated-amazon-eks-clusters-on-aws][3]

[3]: https://aws.amazon.com/solutions/implementations/federated-amazon-eks-clusters-on-aws/

In order to setup a Federated Amazon EKS cluster, we will do the following:
- Apply the bastion host CloudFormation template
- Run `eksfedctl` to create EKS clusters in the appropriate regions
- Ensure the federated EKS clusters are properly setup

The eksfedctl utility will automatically provision the required infrastructure, VPCs, subnets and
setup VPC peering between the bastion host's VPC and the EKS Clusters' VPCs.

![Federated Amazon EKS Cluster architecture][4]
_Federated Amazon EKS Cluster architecture - © Credits AWS_

[4]: https://d1.awsstatic.com/Solutions/Solutions%20Category%20Template%20Draft/Solution%20Architecture%20Diagrams/federated-eks-clusters-ra.12d7f93988d634ebf16d60ed4be42a0bac92c7ed.png

### let's try it out

_Pre-requisite: Make sure you have the sufficient permissions to create the resources mentioned above.
A user policy example is available in the [awslabs/federated-amazon-eks-clusters] repository._

[5]: https://raw.githubusercontent.com/awslabs/federated-amazon-eks-clusters-on-aws/master/source/solution-user-policy.json

#### provision the bastion template

The CloudFormation template for the bastion is pretty straight-forward. Beside the region,
there is no need to configure much, except some extra tags or the default bastion's instance
type. The template is available at the following address:

[federated-amazon-eks-clusters-on-aws.template][6]

[6]: https://s3.amazonaws.com/solutions-reference/federated-amazon-eks-clusters-on-aws/latest/federated-amazon-eks-clusters-on-aws.template

The default template's bastion is a `t3.micro` instance which will be used to provision
the EKS clusters.

#### setup your federated EKS clusters

Once the bastion is up and running, we can access it and provision our clusters.

```console
$ tmux  # the eksfedctl executable requires to be run
$ eksfedctl create --regions us-east-1 us-east-2
```

`eksfedctl` will take care of:
- Creating the VPC, the subnets, peering the VPCs together
- Creating the EKS Cluster, provisioning the instances, scaling groups
- Configuring the EKS Clusters to join the federated cluster

This might take a while, as it involves quite a few operations. Each child
CloudFormation stack is available in its own region.

Upon succesful termination of the eksfedctl command, we can observe our
freshly created clusters by running:

```console
$ kubectl -n kube-federation-system get kubefedclusters
NAME              AGE   READY
federated-eks-1   3s   True
federated-eks-2   1s   True
```

#### using the federated clusters

We can now try out kubefed's features, by setting a NameSpace as federated.

```console
$ kubectl create ns federate-me
namespace/federate-me created
$ kubefedctl federate ns federate-me
I0121 13:36:23.823163     843 federate.go:472] Resource to federate is a namespace. Given namespace will itself be the container for the federated namespace
I0121 13:36:23.837406     843 federate.go:501] Successfully created FederatedNamespace "federate-me/federate-me" from Namespace
```

Kubefed also provides the ability to propagate specific resources:
```console
$ kubectl create cm -n federate-me my-cm --from-literal=data=bob
configmap/my-cm created
$ kubefedctl -n federate-me federate configmap my-cm
I0121 13:41:12.032669     878 federate.go:501] Successfully created FederatedConfigMap "federate-me/my-cm" from ConfigMap
```

When using the `federate` verb, kubefed create a FederatedResource (such as a `FederatedConfigMap`)
and begins propagating the resource to the federated clusters.

Describing the FederatedResource allows visualising the propagation state:
```yaml
Name:         data-cm
Namespace:    federate-me
Labels:       <none>
Annotations:  <none>
API Version:  types.kubefed.io/v1beta1
Kind:         FederatedConfigMap
Metadata: # ...
Spec:
  Placement:
    Cluster Selector:
      Match Labels:
  Template:
    Data:
      Data:  bob
Status:
  Clusters:
    Name:  federated-eks-2
    Name:  federated-eks-1
  Conditions:
    Last Transition Time:  2021-01-21T14:00:02Z
    Last Update Time:      2021-01-21T14:00:02Z
    Status:                True
    Type:                  Propagation
  Observed Generation:     1
Events:
  Type     Reason                 Age   From                           Message
  ----     ------                 ----  ----                           -------
  Normal   CreateInCluster        25m   federatedconfigmap-controller  Creating ConfigMap "federate-me/data-cm" in cluster "federated-eks-1"
  Normal   CreateInCluster        25m   federatedconfigmap-controller  Creating ConfigMap "federate-me/data-cm" in cluster "federated-eks-2"
  Warning  CreateInClusterFailed  25m   federatedconfigmap-controller  Failed to create ConfigMap "federate-me/data-cm" in cluster "federated-eks-1": An update will be attempted instead of a creation due to an existing resource
```
_example output from a federated resource description_

As previously mentionned, federated clusters go way beyong "simply" sharing configs and secrets.
This setup allows you to leverage the power `ReplicaSchedulingPreference` by targeting
FederatedDeployments and applying weight to different clusters, but also
[Multi-Cluster Ingress DNS][7] and [Multi-Cluster Service DNS][8].

[7]: https://github.com/kubernetes-sigs/kubefed/blob/master/docs/userguide.md#multi-cluster-ingress-dns
[8]: https://github.com/kubernetes-sigs/kubefed/blob/master/docs/userguide.md#multi-cluster-service-dns

#### delete the clusters

When creating federated clusters using `eksfedctl`, an env file based on the stack name is created
in the home directory. This file facilitates the deletion of the EKS clusters provisionned earlier.

```yaml
eksfedctl destroy -f ~/{stack name}.env
```

The bastion and the resources created using the CloudFormation template will remain,
allowing to provision other federated EKS clusters easily.

Even if `kubefed` is still marked as in the "alpha" stage, AWS managed to ease
the creation and bootstrapping of High Availability Multi-Region EKS clusters.
We can hope that this will make the project graduate to the "beta" stage in the coming
times.

[**Theo "Bob" Massard**](https://www.linkedin.com/in/tbobm/), Cloud Native Engineer
