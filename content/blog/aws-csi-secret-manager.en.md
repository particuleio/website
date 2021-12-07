---
Title: "AWS Secrets Manager on Kubernetes using AWS Secrets CSI driver Provider"
Date: 2021-05-03
Category: Amazon Web Services
Summary: AWS recently published a new Provider for the Secrets Store CSI Provider, let's see how we can inject AWS Secrets Manager content inside our Kubernetes cluster!
Author: Theo "Bob" Massard
image: images/thumbnails/aws-secret-csi-driver.png
imgSocialNetwork: images/og/aws-secret-csi-driver.png
lang: en
---

Kubernetes provides a way to extend the existing volumes classes by leveraging the
[Container Storage Interface][k8s-csi]. The CSI specifies a way of handling volumes
and data using a common API to ease the development of plugins.

Based on the CSI spec, the [Secrets Store CSI driver][secrets-store-doc] allows to externalize
secret handling, for example to delegate the creation, securisation and rotation of secrets to
a Cloud provider by using different `Providers` that act like backends to interact with the
remote secret source.

_Not that Kubernetes' Secrets aren't secrets per se, but decoding base64 is quite easy._

Using this driver, we can use services such as [Azure Key Vault][azure-key-vault], GCP's
[Google Secret Manager][google-secret-manager] or even non cloud-based services like Hashicorp's
[Vault][hashicorp-vault].

Recently, AWS published a new [backend implementation][gh-aws-provider] for the Secrets Store
CSI Driver [on their blog][aws-blog-secrets-manager-provider] that allows using
[AWS **Secrets Manager**][aws-secrets-manager] as a Secret Provider.

[k8s-csi]: https://kubernetes-csi.github.io/docs/

Let's try it out! :)

[aws-blog-secrets-manager-provider]: https://aws.amazon.com/about-aws/whats-new/2021/04/aws-secrets-manager-delivers-provider-kubernetes-secrets-store-csi-driver/
[aws-secrets-manager]: https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html
[azure-key-vault]: https://docs.microsoft.com/en-us/azure/key-vault/general/overview
[hashicorp-vault]: https://www.vaultproject.io/
[gh-aws-provider]: https://github.com/aws/secrets-store-csi-driver-provider-aws
[google-secret-manager]: https://cloud.google.com/secret-manager/

### What we'll cover in this article

First of all, let's take a look at the solutions and tools we're going to use in this article. We
will follow-up with a test of the AWS Secret Store `Provider` and then find out how we can
use it as a bridge between the AWS **Secrets Manager** and an application's environment.

#### Secrets Manager in a nutshell

[**Secrets Manager**][aws-secrets-manager] is a service provided by AWS to externalize sensitive
informations, such as _password_, _api keys_ and _credentials_ in general.
Being an AWS service, the Secrets Manager takes advantage of the
[existing infrastructure and security][aws-sm-security], meaning that the data can be encrypted
in transit and at rest.

To keep it short, instead of storing credentials on servers or inside configuration files, apps
can lookup a specific secret and retrieve its content, thus reducing the risks of compromising
sensitive informations.

In addition to that, Secrets manager provides some powerful features:

- Being an AWS service, secrets supports ACL through [AWS **IAM**][aws-iam]
  - Fine-grained resource access can be configured to the secret level
  - Secret access can be [monitored][aws-sm-monitoring] using **Cloudwatch** / **Cloudtrail**
- [Automated Secret rotation][aws-sm-rotate] using **Lambdas**, minimizing the risk
caused by leaked credentials

[aws-sm-monitoring]: https://docs.aws.amazon.com/secretsmanager/latest/userguide/monitoring.html
[aws-sm-rotate]: https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets.html
[aws-sm-security]: https://docs.aws.amazon.com/secretsmanager/latest/userguide/security.html
[aws-iam]: https://aws.amazon.com/iam/

#### Secrets Store CSI driver

The [Secrets Store CSI driver][secrets-store-doc] is an implementation of the [CSI][k8s-csi]
oriented towards credential handling using external sources. It is used as an interface between
your Kubernetes applications and a secured credential storage using different `Providers`.

Its goal is to make secrets stored in these external credential sources available in a Kubernetes
cluster through a Kubernetes-native API, the `SecretProviderClass`.

Making credentials available through `Volumes` removes the need for application to be aware
of the secret's location, limiting vendor lock-in as the Secrets Store driver is handling
access. This behaviour also makes it easier to follow the [12factor guidelines][12factor-config]
by making possible, using the [Secret Sync][secrets-store-sync] feature, to inject the credentials
directly in a `Pod` through environment variables.

Repository: <https://github.com/kubernetes-sigs/secrets-store-csi-driver>

[12factor-config]: https://12factor.net/config
[secrets-store-sync]: https://secrets-store-csi-driver.sigs.k8s.io/topics/sync-as-kubernetes-secret.html
[secrets-store-doc]: https://secrets-store-csi-driver.sigs.k8s.io/

#### AWS Secrets and Configuration Provider

With both the AWS Secrets Manager and the Secrets Store introduced, we can now guess what
the [AWS Secrets Store Provider][gh-aws-provider] can offer us.

This implementation allows integrating with Secrets Store as well as the
[Parameter Store][aws-parameter-store], but we will not cover this one in this article as they are
very much alike.

Using this Provider, we will be able to interact with our credentials stored in the Secrets Store
using the Kubernetes API.

[aws-parameter-store]: https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html

#### Architecture

![aws-csi-architecture](/images/aws-csi-secret-provider.png)

_Our application accesses the credentials from the CSI Volume, which is provisioned
by the CSI Driver that fetches the Secret content from AWS Secrets Manager._

### Setup

In this article, we will use the following tools:
- [`awscli`][awscli]: official CLI to interact with AWS services
- [`eksctl`][eksctl]: official CLI made by WeaveWorks to interact with EKS clusters
- [`helm`][helm]: used to manage Helm Charts

[helm]: https://helm.sh/
[eksctl]: https://github.com/weaveworks/eksctl
[awscli]: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html

In order to avoid repeating ourselves, let's variabilize the region in which we want to operate
as well as the cluster name.

```console
export REGION=eu-west-3
export CLUSTERNAME="aws-secret"
```

#### Configure the environment

The AWS **Secrets Store** relies on the [IAM OIDC provider][eks-oidc] EKS plugin in order to link
the IAM roles configured to access the secret with the Kubernetes `ServiceAccounts` used by our
application.

[eks-oidc]: https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html

```console
$ eksctl create cluster --name "$CLUSTERNAME" --region "$REGION" \
    --with-oidc --tags "Env=Demo" --version=1.19 \
    --managed --node-type "t2.large"
[ℹ]  eksctl version 0.40.0
[ℹ]  using region eu-west-3
[ℹ]  setting availability zones to [eu-west-3a eu-west-3b eu-west-3c]
...
[ℹ]  using Kubernetes version 1.19
...
[✔]  EKS cluster "aws-secret" in "eu-west-3" region is ready
```

Once our **EKS** cluster is _ready to roll_, we can start configuring it by installing the
[Secrets Store CSI driver][gh-secrets-store] using the official Helm Chart.

[gh-secrets-store]: https://github.com/kubernetes-sigs/secrets-store-csi-driver

```console
$ helm repo add secrets-store-csi-driver https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/master/charts
"secrets-store-csi-driver" has been added to your repositories
$ helm install -n kube-system csi-secrets-store \
    secrets-store-csi-driver/secrets-store-csi-driver
NAME: csi-secrets-store
LAST DEPLOYED: Mon May  3 15:39:43 2021
NAMESPACE: kube-system
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The Secrets Store CSI Driver is getting deployed to your cluster.

To verify that Secrets Store CSI Driver has started, run:

  kubectl --namespace=kube-system get pods -l "app=secrets-store-csi-driver"

Now you can follow these steps https://secrets-store-csi-driver.sigs.k8s.io/getting-started/usage.html
to create a SecretProviderClass resource, and a deployment using the SecretProviderClass.
```

We now have access to the `SecretProviderClass` CRD, the Kubernetes resource we will
use to configure the mapping between the **CSI volume** and our secret stored
in AWS **Secrets Manager**.

As we have all the necessary requirements configured, we can proceed with the installation of
the AWS **Secrets Manager** `Provider` using the `aws-provider-installer.yaml` manifest
from the Github Repository.

```console
$ kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml
serviceaccount/csi-secrets-store-provider-aws created
clusterrole.rbac.authorization.k8s.io/csi-secrets-store-provider-aws-cluster-role created
clusterrolebinding.rbac.authorization.k8s.io/csi-secrets-store-provider-aws-cluster-rolebinding created
daemonset.apps/csi-secrets-store-provider-aws created
```

Everything should be properly setup by now !

[aws-driver-image]: public.ecr.aws/aws-secrets-manager/secrets-store-csi-driver-provider-aws:latest

#### Demo time !

Let's try out our configuration by defining a Secret in **Secrets Manager** and accessing it from
a `Pod` in our **EKS** cluster.

First, we create a convincing payload in `secretsmanager` using `awscli`.

```console
$ aws --region "$REGION" secretsmanager create-secret --name creds --secret-string '{"username":"bob", "password":"csi-driver"}'
{
    "ARN": "arn:aws:secretsmanager:eu-west-3:111111111111:secret:creds-lhRfik",
    "Name": "creds",
    "VersionId": "c7a8ee03-f1f2-4e4c-8c08-c2b1160b898e"
}
```

Afterwards, we need to create an **IAM** Policy and attach it to our **IAM** service account
which will be used by our Kubernetes `ServiceAccount`.

```console
$ POLICY_ARN=$(aws --region "$REGION" --query Policy.Arn --output text iam create-policy --policy-name validate-csi-setup-policy --policy-document '{
    "Version": "2012-10-17",
    "Statement": [ {
        "Effect": "Allow",
        "Action": ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
        "Resource": ["arn:*:secretsmanager:*:*:secret:creds-??????"]
    } ]
}')
$ eksctl create iamserviceaccount --name validate-csi-setup-sa --region="$REGION" --cluster "$CLUSTERNAME" --attach-policy-arn "$POLICY_ARN" --approve --override-existing-serviceaccounts
[ℹ]  eksctl version 0.40.0
[ℹ]  using region eu-west-3
[ℹ]  1 existing iamserviceaccount(s) (kube-system/aws-node) will be excluded
[ℹ]  1 iamserviceaccount (default/validate-csi-setup-sa) was included (based on the include/exclude rules)
...
[ℹ]  created serviceaccount "default/validate-csi-setup-sa"
```

The `eksctl create iamserviceaccount` configured an **IAM** role, attached the **IAM** Policy we previously
created and created a serviceaccount in the `default` namespace.

We can now access our secret from our Kubernetes cluster !

First of all, we create a `SecretProviderClass` with our `aws` provider:
```yaml
---
# secret-provider.yaml
apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
kind: SecretProviderClass
metadata:
  name: aws-secret-credentials
spec:
  provider: aws
  parameters:
    objects: |
        - objectName: "creds"  # our secret
          objectType: "secretsmanager"
```
And we apply the manifest:
```console
$ kubectl apply -f secret-provider.yaml
secretproviderclass.secrets-store.csi.x-k8s.io/aws-secret-credentials created
```

Then, we simply need to create an example resource that will mount the **CSI Volume** and
we will be able to access our secret.

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-csi-setup
  labels:
    app: nginx
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      serviceAccountName: validate-csi-setup-sa  # our IAM-capable service account
      volumes:
        - name: secrets-store-inline
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: "aws-secret-credentials"  # our SecretProviderClass
      containers:
        - name: test-csi-setup
          image: nginx
          volumeMounts:
            - name: secrets-store-inline
              mountPath: "/mnt/secrets-store"
              readOnly: true
```

Finally, we can create our test `Deployment` and check that the file based on our secret's name
is available inside our `Pods`.

```console
$ kubectl apply -f deployment.yml
deployment.apps/test-csi-setup created
$ kubectl exec -it $(kubectl get pods | awk '/test-csi-setup/{print $1}' | head -1) -- cat /mnt/secrets-store/creds; echo
{"username":"bob", "password":"csi-driver"}
```

Great ! We managed to access our Secrets Store content through the mounted **CSI volume** !

### Application use-case

Still, defining credentials [is not considered the recommended approach][12factor-config], but we
can take profit of the [Secret Sync][secrets-store-sync] feature of the Secrets CSI driver to
inject our secret directly into the `Pod` environment variables !

We'll start by defining an API KEY (`service-api-key`) that will be used in a `Pod`.
For this scenario, we want to be able to fetch the secret's content from the environment.

Let's repeat the steps we did previously, this time simply storing a string in AWS Secrets Manager.

```console
$ aws --region "$REGION" secretsmanager create-secret --name service-api-key --secret-string 'mysecretapikey'
{
    "ARN": "arn:aws:secretsmanager:eu-west-3:111111111111:secret:service-api-key-1G5hf7",
    "Name": "service-api-key",
    "VersionId": "8a02128e-5fa8-4876-b735-63df830564f5"
}
$ POLICY_ARN=$(aws --region "$REGION" --query Policy.Arn --output text iam create-policy --policy-name service-api-key-secret-policy --policy-document '{
    "Version": "2012-10-17",
    "Statement": [ {
        "Effect": "Allow",
        "Action": ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
        "Resource": ["arn:*:secretsmanager:*:*:secret:service-api-key-??????"]
    } ]
}')
$ eksctl create iamserviceaccount --name service-api-key-sa --region="$REGION" --cluster "$CLUSTERNAME" --attach-policy-arn "$POLICY_ARN" --approve
```

We have our secret stored in AWS, our service account and now we need to create a
`SecretProviderClass` that will synchronize a `Secret` upon mounting the `Volume`.

This is done by defining a `secretObjects` entry, with `secretName` being the name that we will
reference when configuring the `API_KEY` environment variable.

```yaml
---
apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
kind: SecretProviderClass
metadata:
  name: aws-secret-application
spec:
  provider: aws
  secretObjects:
    - secretName: application-api-key  # the k8s secret name
      type: Opaque
      data:
        - objectName: secret-api-key  # reference the corresponding parameter
          key: api_key
  parameters:
    objects: |
      - objectName: "secret-api-key"  # the AWS secret
        objectType: "secretsmanager"
```

We now have to reference the **CSI Volume** using the `SecretProviderClass` name, mount it in
the `Pod` and create an environment variable referencing the `application-api-key` `Secret`.

```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: application
spec:
  serviceAccountName: service-api-key-sa
  volumes:
    - name: api-secret
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: "aws-secret-application"
  containers:
    - name: application
      image: busybox
      command:
        - "sleep"
        - "3600"
      env:
        - name: API_KEY
          valueFrom:
            secretKeyRef:
              name: application-api-key
              key: api_key
      volumeMounts:
        - name: api-secret
          mountPath: "/mnt/secrets-store"
          readOnly: true
```

After applying this manifest, we _should_ be able to get our AWS Secret's content directly from
the env var `API_KEY`.

```console
$ kubectl exec -it application -- env | grep API_KEY
API_KEY=mysecretapikey
```

Success ! We have integrated our Secret's content in our application's environment.

### In conclusion

The AWS Secret `Provider` is a great addition to the Secrets Store CSI Driver.
It integrates perfectly in the Kubernetes and reduces the need for application to be cloud-aware.
In addition to that, using the AWS **Secrets Manager** allows to implement automated
[password rotation][aws-sm-rotate] using **Lambdas**, reducing the risk of compromised credentials.

[**Theo "Bob" Massard**](https://www.linkedin.com/in/tbobm/), Cloud Native Engineer
