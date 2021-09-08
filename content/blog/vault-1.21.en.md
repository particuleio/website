---
Title: Repair Hashicorp Vault on Kubernetes 1.21
Date: 2021-09-04
Category: Kubernetes
Summary: Solve your struggles with Vault on latest Kubernetes releases
Author: Kevin Lefevre
image: images/thumbnails/vault.png
lang: en
---

Lot's of users saw their [Haschicorp Vault cluster
broke](https://github.com/external-secrets/kubernetes-external-secrets/issues/721):
when updating to Kubernetes version >= 1.21.

In fact Kubernetes enabled [Service Account Issuer
Discovery](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#service-account-issuer-discovery)
to be more compliant with [OIDC
specs](https://openid.net/specs/openid-connect-discovery-1_0.html) and therefore
broke basic [Vault Kubernetes auth configuration](https://www.vaultproject.io/docs/auth/kubernetes).

If you see this error and are on Kubernetes version >= 1.21 you are probably
impacted:

```
2021-07-25T06:12:43.359Z [INFO]  sink.file: creating file sink
2021-07-25T06:12:43.359Z [INFO]  sink.file: file sink configured: path=/home/vault/.vault-token mode=-rw-r-----
2021-07-25T06:12:43.361Z [INFO]  sink.server: starting sink server
2021-07-25T06:12:43.361Z [INFO]  template.server: starting template server
2021-07-25T06:12:43.361Z [INFO]  auth.handler: starting auth handler
[INFO] (runner) creating new runner (dry: false, once: false)
2021-07-25T06:12:43.361Z [INFO]  auth.handler: authenticating
[INFO] (runner) creating watcher
2021-07-25T06:13:43.362Z [ERROR] auth.handler: error authenticating: error="context deadline exceeded" backoff=1s
2021-07-25T06:13:44.363Z [INFO]  auth.handler: authenticating
```

No worries as this is easily fixable, there are basically two options:

* enable `disable_iss_validation=true` to bypass the new behavior (not
    recommended)

* update your Vault Kubernetes auth config to be compliant with the new format by
    adding the `issuer` field to Kubernetes auth config (recommended)

The later is of course the way to go, but most of the issue tell you to add
`https://kubernetes.default.svc.cluster.local` as an issuer but be careful this
might not be the case in your cluster, especially if your are using managed
Kubernetes clusters like [AWS EKS](https://aws.amazon.com/fr/eks/) which include
a specific OIDC cluster issuer.

# Update Vault configuration to be compliant with new specifications

This error is actually quite simple to fix and I'm just compiling here the
conclusion of various issues I've stumble unto for the sake of history and
archiving it here because navigating Github issues is not the more fun you can
have in a day.

Let's get our cluster issuer URL, this example use an EKS cluster which differs
from vanilla self manage Kubernetes.

```
curl --silent http://127.0.0.1:8001/api/v1/namespaces/default/serviceaccounts/default/token \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{"apiVersion": "authentication.k8s.io/v1", "kind": "TokenRequest"}' \
  | jq -r '.status.token' \
  | cut -d. -f2 \
  | base64 -d | jq .iss

https://oidc.eks.eu-west-1.amazonaws.com/id/REDACTED123456
```

That's it let's now update our Vault config, from inside a Vault pods:

```
vault write auth/kubernetes/config \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  issuer="$YOUR_PREVIOUSLY_COMPUTED_ISSUER \
```

Now you should be good to go and this nasty error should be gone.

This article is part of a new take on articles where we focus on various power
user issues we encounter and try to sum up our investigation (basicaly we read
Github Issues and stackoverflow for you).

Vault for AWS EKS, with KMS support out of the box is included in our awesome
Terraform module
[`terraform-kubernetes-addons`](https://github.com/particuleio/terraform-kubernetes-addons/tree/main/modules/aws)
which give you all the critical addons with the best default config you need to
get a production ready EKS cluster. For the entire stack don't hesitate to check
our [Terragrunt powered EKS solution](https://github.com/particuleio/teks)

Don't hesitate to [reach us](mailto:contact@particule.io) on Github or through our website if you need any help
navigating the Kubernetes ecosystem for your projects.

[Particule](https://particule.io)
