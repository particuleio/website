---
Title: "Data-driven scaling on Kubernetes using Keda"
Date: 2021-06-19
Category: Kubernetes
Summary: 
Author: Theo "Bob" Massard
image: images/thumbnails/aws-secret-csi-driver.png
imgSocialNetwork: images/og/aws-secret-csi-driver.png
lang: en
---

One of the advantages of using cloud-based solution is their elasticity.
By design, we should be able to scale in and out based on a list of metrics.

This allows us to easily go from being able to serve 100 requests/s to multiple
thousands, increasing the processing power of our applications in response to
a sudden burst of traffic for example.

Scaling and auto-scaling are features that already exist in Kubernetes and are
widely used.

By default, we can scale manually in Kubernetes using the [`kubectl scale`][scale-kubectl]
command or even by simply editing the number of replicas in a `Deployment`
or a `StatefulSet` ([scale a `Deployment`][scale-deploy]).

[scale-kubectl]: https://kubernetes.io/docs/reference/kubectl/cheatsheet/#scaling-resources
[scale-deploy]: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#scaling-a-deployment

In addition to that we are able to automate scaling based on the used resources,
using the [`HorizontalPodAutoscaler`][k8s-hpa] that leverages the
[`metrics-server`][gh-metrics-server]. This addon exposes metrics regarding
the `Pods` **RAM** and **CPU** consumption.

[k8s-hpa]: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
[gh-metrics-server]: https://github.com/kubernetes-sigs/metrics-server

This works quite well when aiming for auto-scaling in the "frontend" department,
such as for exposing HTTP APIs. Yet sometimes a high **CPU** usage or **RAM**
usage can also be considered "normal", such as during image processing or
buffering. In more complex environments with different, more asynchronous
processing methods such as batch processing or event-driven processing, we
might end up looking for smarter metrics. Those metrics might also be more
business-oriented, if we're dealing with a SaaS product.

[Keda][keda-main] (for _Kubernetes Event-Driven Autoscaling_) implements a
scaling pattern ([keda - concepts][keda-concepts]) that enables using this kind of _smarter_ criterias as references for autoscaling. It implements a custom
architecture that will manage the scaling of different Kubernetes resources
based on external metric sources.

[keda-main]: https://keda.sh/
[keda-concepts]: https://keda.sh/docs/2.3/concepts/

#### What is Keda  - draft

Keda is a `Controller` that allows scaling that supports it (`Deployments`,
`StatefulSets`, `Jobs`, ...) using an external source of metrics (other than
the `metrics-server`) as a criteria to compute
how many replicas we must have based on simple logical operators.

We will first define the source of the metric, called a Scaler.
The Scalers are the components that will expose a metric of a 3rd party origin
that can be a lot of things. The list of Scalers include:
- Items in an S3 bucket
- Database queries to SQL and no-SQL backends
- Content of a Redis List

Once we have a source, we can specify the metric we want to observe, such as
the number of items in a Queue, the number of files in an S3 directory.
This metric will expose to the Keda controller how many items can a worker
process.

For example, consider we have specified that a worker (the target object that will
scale) deployed through a `Deployment` can handle 5 items in a queue.
If we have around 20 items in the Trigger's queue, we will observe that we have
4 Pods.
If we go down to 5 items in the Queue, we will scale down to a single worker.

#### How to implement Keda

The only requirement besides running a Kubernetes cluster is to implement
a Microservice architecture.

As mentioned in the Well Architected Framework by AWS
([Loosely Coupled Scenarios][wa-scenarios]), you should use a loosely decoupled
architecture to enable asynchronous processing and leverage cloud-based services.

[wa-scenarios]: https://docs.aws.amazon.com/wellarchitected/latest/high-performance-computing-lens/loosely-coupled-scenarios.html

Keda's installation is pretty straight forward, as we can easily get our hands
on the [official Helm Chart][gh-helm] that will install the `CRDs`,
the `keda-operator` and the `keda-operator-metrics-apiserver`.

[gh-helm]: https://github.com/kedacore/charts

We simply need to add Keda's Helm Repository and install the Chart
`kedacode/keda`.

```console
$ helm repo add kedacore https://kedacore.github.io/charts
"kedacore" has been added to your repositories
$ helm repo update
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "kedacore" chart repository
Update Complete. ⎈Happy Helming!⎈
$ helm install keda kedacore/keda --namespace keda
NAME: keda
LAST DEPLOYED: Thu Jun  3 09:40:09 2021
NAMESPACE: keda
STATUS: deployed
REVISION: 1
TEST SUITE: None
```

In a couple of commands, we have installed `Keda` in our Kubernetes Cluster.
We can observe what got installed in our cluster.

```bash
$ k api-resources --api-group=keda.sh
NAME                            SHORTNAMES               APIVERSION         NAMESPACED   KIND
clustertriggerauthentications   cta,clustertriggerauth   keda.sh/v1alpha1   false        ClusterTriggerAuthentication
scaledjobs                      sj                       keda.sh/v1alpha1   true         ScaledJob
scaledobjects                   so                       keda.sh/v1alpha1   true         ScaledObject
triggerauthentications          ta,triggerauth           keda.sh/v1alpha1   true         TriggerAuthentication
$ k get pods -n keda
NAME                                              READY   STATUS    RESTARTS   AGE
keda-operator-6d44598949-lpxvl                    1/1     Running   0          111s
keda-operator-metrics-apiserver-db85c656f-wnlzv   1/1     Running   0          111s
```

The `CRDs` have been installed and the `keda-operator` `Pods` are running.

We can now aim for a more realistic configuration.

### Try out Keda

First, let's setup an AWS infrastructure to explore Keda's capabilities.
We will aim for a simple infrastructure with an EKS Cluster and an SQS Queue
as our message-broker component.

Using [`particuleio/tEKS`][gh-particule-teks], we will create our own Terraform
infrastructure. The Github repository is available here: [`tbobm/teks-keda-sqs`][gh-tbobm-teks]

[gh-particule-teks]: https://github.com/particuleio/teks/
[gh-tbobm-teks]: https://github.com/tbobm/teks-keda-sqs/

- [ ] SQS

After having setup the networking infrastructure, we will create
our EKS Cluster with IRSA enabled to easily authenticate our application.

_Complete infrastructure can be found at [tbobm/teks-keda-sqs][gh-tbobm-teks]._

```hcl
module "eks" {
  source = "terraform-aws-modules/eks/aws"

  enable_irsa = true

  cluster_version = "1.20"

  node_groups = {
      # our node group definitions
      # ...
    }
  }
}
```

Afterwards, we simply need to create the cluster by applying our configuration.

```console
$ terraform apply
...
Apply complete! Resources: 25 added, 0 changed, 0 destroyed.
```

```bash
$ POLICY_ARN=$(aws --region eu-west-3 --query Policy.Arn --output text iam create-policy --policy-name teks-sqs --policy-document '{
   "Version": "2012-10-17",
   "Statement": [{
      "Effect": "Allow",
      "Action": ["sqs:*"],
      "Resource": ["arn:aws:sqs:*:*:*"]
   }]  
}')
$ echo $POLICY_ARN 
arn:aws:iam::303743559525:policy/teks-sqs
$ eksctl create iamserviceaccount --name aws-sqs --region=eu-west-3 --cluster tbobm-demo --attach-policy-arn "$POLICY_ARN" --approve --override-existing-serviceaccounts
[ℹ]  eksctl version 0.40.0
[ℹ]  using region eu-west-3
[ℹ]  1 iamserviceaccount (default/aws-sqs) was included (based on the include/exclude rules)
[!]  serviceaccounts that exists in Kubernetes will be excluded, use --override-existing-serviceaccounts to override
[ℹ]  1 task: { 2 sequential sub-tasks: { create IAM role for serviceaccount "default/aws-sqs", create serviceaccount "default/aws-sqs" } }
[ℹ]  building iamserviceaccount stack "eksctl-tbobm-demo-addon-iamserviceaccount-default-aws-sqs"
[ℹ]  deploying stack "eksctl-tbobm-demo-addon-iamserviceaccount-default-aws-sqs"
[ℹ]  waiting for CloudFormation stack "eksctl-tbobm-demo-addon-iamserviceaccount-default-aws-sqs"
[ℹ]  created serviceaccount "default/aws-sqs"
```

```yaml
$ k create secret generic sqs-queue --from-literal=SQS_QUEUE_URL=https://sqs.eu-west-3.amazonaws.com/303743559525/sqs-keda-demo -o yaml --dry-run=client > secret.yaml
secret/sqs-queue created
```

#### Code

- [ ] Producer
- [ ] Consumer

#### Demo time !

- [ ] Show initial setup (Deployment)

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: consumer
  name: consumer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: consumer
  template:
    metadata:
      labels:
        app: consumer
    spec:
      serviceAccountName: aws-sqs
      containers:
        - image: ghcr.io/tbobm/teks-keda-sqs-consumer:main
          name: consumer
          env:
            - name: AWS_DEFAULT_REGION
              value: "eu-west-3"
            - name: SQS_QUEUE_URL
              valueFrom:
                secretKeyRef:
                  name: sqs-queue
                  key: SQS_QUEUE_URL
```

- [ ] Show Keda configuration
```yaml
---
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: sqs-trigger-auth
  namespace: default
spec:
  secretTargetRef:
    - parameter: awsAccessKeyID
      name: sqs-admin
      key: AWS_ACCESS_KEY_ID
    - parameter: awsSecretAccessKey
      name: sqs-admin
      key: AWS_SECRET_ACCESS_KEY
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: sqs-consumer
  namespace: default
spec:
  scaleTargetRef:
    name: consumer
  triggers:
    - type: aws-sqs-queue
      authenticationRef:
        name: sqs-trigger-auth
      metadata:
        queueName: sqs-keda-demo
        queueURL: https://sqs.eu-west-3.amazonaws.com/303743559525/sqs-keda-demo
        queueLength: '5'
        identityOwner: pod
        awsRegion: 'eu-west-3'
```

```bash
$ k create secret generic sqs-admin --from-literal=AWS_ACCESS_KEY_ID=XXXXXX --from-literal=AWS_SECRET_ACCESS_KEY='XXXXXX'
secret/sqs-admin created
```

- [ ] Start Producer Job

```yaml
k get deploy
NAME       READY   UP-TO-DATE   AVAILABLE   AGE
consumer   0/0     0            0           27h
```

```yaml
---
apiVersion: batch/v1
kind: Job
metadata:
  labels:
    app: producer
  name: producer
spec:
  completions: 20
  parallelism: 20
  template:
    metadata:
      labels:
        app: producer
    spec:
      serviceAccountName: aws-sqs
      restartPolicy: Never
      containers:
        - image: ghcr.io/tbobm/teks-keda-sqs-producer:main
          name: producer
          env:
            - name: AWS_DEFAULT_REGION
              value: "eu-west-3"
            - name: SQS_QUEUE_URL
              valueFrom:
                secretKeyRef:
                  name: sqs-queue
                  key: SQS_QUEUE_URL
```

```yaml
$ k get job -w
NAME       COMPLETIONS   DURATION   AGE
producer   0/20          10s        10s
producer   1/20          2m45s      2m45s
producer   2/20          2m45s      2m45s
producer   3/20          2m46s      2m46s
producer   4/20          2m46s      2m46s
producer   5/20          2m48s      2m48s
producer   6/20          2m48s      2m48s
producer   7/20          2m48s      2m48s
producer   8/20          2m48s      2m48s
producer   9/20          2m48s      2m48s
producer   10/20         2m49s      2m49s
producer   11/20         2m49s      2m49s
producer   12/20         2m50s      2m50s
producer   13/20         3m         3m
producer   14/20         3m19s      3m19s
producer   15/20         3m27s      3m27s
producer   16/20         3m28s      3m28s
producer   17/20         3m28s      3m28s
producer   18/20         3m29s      3m29s
producer   19/20         3m30s      3m30s
producer   20/20         3m30s      3m30s
```

- [ ] Show scaling
```yaml
$ k get deploy -w
NAME       READY   UP-TO-DATE   AVAILABLE   AGE
consumer   0/0     0            0           47h
consumer   0/1     0            0           47h
consumer   0/3     1            0           47h
consumer   0/3     3            0           47h
consumer   1/3     3            1           47h
consumer   2/3     3            2           47h
consumer   3/3     3            3           47h
consumer   3/0     3            3           47h
consumer   0/0     0            0           47h
```

- [ ] Show downscaling

### In conclusion

- [ ] Mention other interesting scalers
- [ ] Mention roadmap ?
- [ ] Keda kewl

[**Theo "Bob" Massard**](https://www.linkedin.com/in/tbobm/), Cloud Native Engineer
