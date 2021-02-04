---
Title: Automatic image update in Git with FluxCD
Date: 2021-02-03
Category: Kubernetes
Summary: "This feature had disappeared from FluxCD since the v2 but it's back
now and allows you to automatically track image updates !"
Author: Romain Guichard
image: images/thumbnails/flux-horizontal-color.png
imgSocialNetwork: images/og/flux-image-update.png
lang: en
---

It's been a while since we talked about Gitops in this blog. It's a topic we
had broadly covert and you can find our articles here :

- [Kubernetes Kustomize with FluxCD](https://particule.io/en/blog/flux-kustomize/)
- [Canary Deployment with ArgoCD](https://particule.io/en/blog/argocd-canary/)
- [Flux joins the
  CNCF](https://particule.io/en/blog/weave-flux-cncf-incubation/)

## Quick reminder about Gitops

Gitops is a set of tools and practices to deploy your applications and your
infrastructure. Anything defined as code really. This code is stored in a Git
repository and acts as your **single source of truth**. Gitops mechanisms will
ensure that the real state (the one in your Kubernetes cluster for example)
matches your **desired state** (the one defined in Git) and will reconcile both at all
time.

Why is it good ?

First, you don't need to operate your cluster with `kubectl`, the Gitops agent
(we'll talk about implementations later) will automatically apply your changes
as soon as they are committed to git. Git will be your only tool to interact
with Kubernetes. Code review, PR, MR etc, will allow you to precisely control
what is applied to your cluster.

These are the 4 principles of Gitops:

- Your system is defined declaratively
- The desired state of your system is stored in Git which is your single source
  of truth
- Changes are applied as soon as they are validated
- A process of reconciliation ensure the synchronisation between real state and
  desired state

The two leading Gitops solutions are [FluxCD](https://fluxcd.io/) and
[ArgoCD](https://argoproj.github.io/argo-cd/). Both are members of the CNCF.
FluxCD follows the specifications of the Gitops toolkit while ArgoCD follows
those of the Gitops Engine.

As we already talked about Gitops (in this article and the previous ones), we
won't come back on those principles and we are going to present a new feature
in FluxCD v2 : **the image update feature**.

This feature allows Flux to track the changes of your container image into a
container registry and apply those changes into your Kubernetes cluster.

## Didn't it already exist ?

Yes indeed. This feature exists in FluxCD v1 but was removed in FluxCD v2.

Tout à fait, mais dans FluxCD v1, depuis la v2 cette fonction avait disparu
mais faisait parti des priorités sur la roadmap.

This feature, like the one in FluxCD v1, will track new versions of your image
and will update your desired state in Git with the new image. You can decide to
track every new images or only the ones matching a semver rule or a regex. Once
your desired state is updated, FluxCD reconciliation process will trigger an
update on your Kubernetes cluster.

One could consider that this feature is out of the scope of Gitops since your
container registry can be considered as a second source of truth. This is why
you won't find this feature with ArgoCD.

This feature is now back in FlucCD v2 in alpha.

## Let's play !

Let's bootstrap a Flux environment then we will update it to enable the image
update feature.

You will need a GitHub personnal token with all `repo` access permissions:

![PAT](/images/flux/github-pat.png)

```console
$ curl -s https://toolkit.fluxcd.io/install.sh | sudo bash
$ flux check --pre
$ export GITHUB_TOKEN=YOUR-TOKEN
$ flux bootstrap github --owner=rguichard --repository=fluxcd-demo --path=clusters/fluxcd-demo --personal
► connecting to github.com
✔ repository cloned
✚ generating manifests
✔ components are up to date
► installing components in flux-system namespace
namespace/flux-system created
customresourcedefinition.apiextensions.k8s.io/alerts.notification.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/buckets.source.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/gitrepositories.source.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/helmcharts.source.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/helmreleases.helm.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/helmrepositories.source.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/kustomizations.kustomize.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/providers.notification.toolkit.fluxcd.io created
customresourcedefinition.apiextensions.k8s.io/receivers.notification.toolkit.fluxcd.io created
serviceaccount/helm-controller created
serviceaccount/kustomize-controller created
serviceaccount/notification-controller created
serviceaccount/source-controller created
clusterrole.rbac.authorization.k8s.io/crd-controller-flux-system created
clusterrolebinding.rbac.authorization.k8s.io/cluster-reconciler-flux-system created
clusterrolebinding.rbac.authorization.k8s.io/crd-controller-flux-system created
service/notification-controller created
service/source-controller created
service/webhook-receiver created
deployment.apps/helm-controller created
deployment.apps/kustomize-controller created
deployment.apps/notification-controller created
deployment.apps/source-controller created
networkpolicy.networking.k8s.io/allow-scraping created
networkpolicy.networking.k8s.io/allow-webhooks created
networkpolicy.networking.k8s.io/deny-ingress created
Waiting for deployment "source-controller" rollout to finish: 0 of 1 updated replicas are available...
deployment "source-controller" successfully rolled out
deployment "kustomize-controller" successfully rolled out
Waiting for deployment "helm-controller" rollout to finish: 0 of 1 updated replicas are available...
deployment "helm-controller" successfully rolled out
Waiting for deployment "notification-controller" rollout to finish: 0 of 1 updated replicas are available...
deployment "notification-controller" successfully rolled out
✔ install completed
► configuring deploy key
✔ deploy key configured
► generating sync manifests
► applying sync manifests
◎ waiting for cluster sync
✔ bootstrap finished
```

Unlike Flux v1 which was composed of one controller, Flux v2 uses the Gitops
toolkit which contains many controllers and can be configure using CRD:

- Source Controller
- Kustomize Controller
- Helm Controller
- Notification Controller
- Image Automation Controller

<https://toolkit.fluxcd.io/components/>

All these components are now installed and you can commit your Kubernetes
resources into the Git repository Flux created for you (`fluxcd-demo` in my
case). Reconciliation process kicks in every minute.

## Image automation

Image Automation controller isn't installed by default (since it's an alpha
feature) et you need to reconfigure Flux. The `flux bootstrap` command is
idempotent and you can run it again with the new parameters:

```console
--components-extra=image-reflector-controller,image-automation-controller
```

We are going to create three versions of our image.

```console
$ docker tag particule/helloworld particule/helloworld:v1.0.0
$ docker tag particule/helloworld particule/helloworld:v1.1.0
$ docker tag particule/helloworld particule/helloworld:v2.0.0
```

Use the CRD ImageRepository to track your image:

```yaml
apiVersion: image.toolkit.fluxcd.io/v1alpha1
kind: ImageRepository
metadata:
  name: helloworld
  namespace: flux-system
spec:
  image: particule/helloworld
  interval: 1m0s
```

Then, use the CRD ImagePolicy to specify which version you want to track.

```yaml
apiVersion: image.toolkit.fluxcd.io/v1alpha1
kind: ImagePolicy
metadata:
  name: helloworld
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: helloworld
  policy:
    semver:
      range: '>= 1.0.0 <2.0.0'
```

I choose to track every versions between `1.0.0` and `2.0.0`. Only
`particule/helloworld:1.0.0` and `particule/helloworld:1.1.0` should be concerned
by the update, `particule/helloworld:2.0.0` shouldn't.

Those CRD can set the tracking up but they will not trigger an update into the
Git repository.

You can check that the tracking works as expected:

```console
$ flux get image policy helloworld
NAME      	READY	MESSAGE                                                       	LATEST IMAGE
helloworld	True 	Latest image tag for 'particule/helloworld' resolved to: 1.1.0	particule/helloworld:1.1.0
$ flux get image repository helloworld
NAME      	READY	MESSAGE                       	LAST SCAN           	SUSPENDED
helloworld	True 	successful scan, found 11 tags	2021-02-03T23:45:03Z	False
```

We see the last image I push and match my semver rule : `1.1.0`.

Let's configure Flux to update our Git repository when a new version is found
by our ImagePolicy. Flux needs write permission to your Git repository to
trigger the reconciliation process.

Two things here. First create the new resource ImageUpdateAutomation then
modify your application to tell Flux which image would need to be updated. To
do so, you need to add a marker to the container spec:
`# {"$imagepolicy": "POLICY_NAMESPACE:POLICY_NAME"}`.

```yaml
spec:
  containers:
  - name: container
    image: particule/helloworld:1.0.0 # {"$imagepolicy": "flux-system:helloworld"}
```

```yaml
apiVersion: image.toolkit.fluxcd.io/v1alpha1
kind: ImageUpdateAutomation
metadata:
  name: helloworld
  namespace: flux-system
spec:
  checkout:
    branch: main
    gitRepositoryRef:
      name: helloworld
  commit:
    authorEmail: fluxcdbot@particule.io
    authorName: fluxcdbot
    messageTemplate: 'update image'
  interval: 1m0s
  update:
    strategy: Setters
```

Check that the Deploy Key in your Git repository has write permission. If that
is not the case, you can get the public key used and reconfigure your Github
repository:

```
$ kubectl -n flux-system get secret flux-system -o json | jq '.data."identity.pub"' -r | base64 -d
```

Apply, wait and watch:

```console
$ kubectl get deploy helloworld -o json | jq -r '.spec.template.spec.containers[0].image'
particule/helloworld:1.1.0
```

Our Deployment has been updated with the new image and our Git repository has
been also updated.

```console
commit 75ba609fa4fc7b6bf9c3eb742acf1743a1cb4d7b (HEAD -> main, origin/main, origin/HEAD)
Author: fluxcdbot <fluxcdbot@particule.io>
Date:   Thu Feb 4 09:27:40 2021 +0000

    update image

diff --git a/clusters/fluxcd-demo/fullapp.yaml b/clusters/fluxcd-demo/fullapp.yaml
index 636eda1..b1b224d 100644
--- a/clusters/fluxcd-demo/fullapp.yaml
+++ b/clusters/fluxcd-demo/fullapp.yaml
@@ -1,4 +1,3 @@
----
 apiVersion: apps/v1
 kind: Deployment
 metadata:
@@ -16,10 +15,10 @@ spec:
         app: helloworld
     spec:
       containers:
-        image: particule/helloworld # {"$imagepolicy": "flux-system:helloworld"}
+        image: particule/helloworld:1.1.0 # {"$imagepolicy": "flux-system:helloworld"}
```


At the end we can push a new image `2.0.0` and see that it would not trigger an
update since it doesn't match our ImagePolicy.

```console
$ docker push particule/helloworld:2.0.0
```

## Conclusion

Yes, this is deja-vu. Nevertheless, it's back ! Maybe that was one of the
reason keeping you from using FluxCD v2 ?

L'équipe [Particule](https://particule.io)
