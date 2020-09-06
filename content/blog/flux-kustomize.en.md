---
Title: Kubernetes Kustomize with Flux CD
Date: 2020-09-06
Category: Kubernetes
Summary: Enjoy Kustomize, integrated to Flux CD, to deploy your Kubernete YAML on multiple environments. All-in with the GitOps way.
Author: Romain Guichard
image: images/thumbnails/flux-horizontal-color.png
imgSocialNetwork: images/og/kustomize-flux.png
lang: en
---

Today, we are going to take about two subjects, the first one is kind of the
leitmotiv of this blog: [GitOps](https://www.weave.works/technologies/gitops/),
the other one is the new here: [Kustomize](https://github.com/kubernetes-sigs/kustomize).

We are long time users of [Helm](https://helm.sh/). Helm is a templating
solution for Kubernetes based on [Go
template](https://golang.org/pkg/text/template/). It's kind of the _de facto_
standart for Kubernetes application packaging. You can find official Helm
Charts as well as community Charts for pretty much every middelwares you can
think of.

Some of them are very thorough and they will keep you from reinvente the wheel
each time you want to deploy a Nginx server for example. But some time, we
have to package your own application and let's face it, creating and
maintaining, efficiently, a Helm package is not that easy. And no official Chart to help
you here.


First thing that comes to mind is to not use Helm Chart and stay with the
native YAML manifests. You shall have one manifest per environment. The main
con is the invevitable code duplication that will occur if you have many
environments. Code duplication is time consuming and the source of many human
errors.

Templating tools can solve those problems. There are many of them, each one
with their own features :

* [Helm](https://helm.sh/)
* [Kustomize](https://github.com/kubernetes-sigs/kustomize)
* [kpt](https://github.com/GoogleContainerTools/kpt)
* [k14's ytt](https://get-ytt.io/)

This article is not about benchmarking these solutions, they are
actually quite different and in the end will achieve the same purpose. We will
focus on [Kustomize](https://github.com/kubernetes-sigs/kustomize).

Helm is clearly the most used but, imo, it's not the simplest to use. When
you're starting with Kubernetes templating tools, Kustomize could be a
quick-win, espacially since you don't have to learn Go Template (used by Helm)
or anything else.

### Let's start with Kustomize

[Kustomize](https://github.com/kubernetes-sigs/kustomize), used to be a
standalone tool and is now a fully integrated into
[`kubectl`](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)
since Kubernetes v1.14.

Kustomize is *Kubernetes native* and doesn't need advanced templating
knowledge. Like the command `kubectl patch`, Kustomize use an equivalent
principle to create complexe Kubernetes manifests.

Let's start with this
[git repository](https://github.com/particuleio/gitops-demo/kustomize)
and a Kubernetes cluster.

Create two `namespaces`:

```console
kubectl create ns preprod
kubectl create ns prod
```

The directory structure is as follow:

```console
.
├── base
│   ├── helloworld-de.yaml
│   ├── helloworld-hpa.yaml
│   ├── helloworld-svc.yaml
│   └── kustomization.yaml
├── preprod
│   └── kustomization.yaml
└── prod
    ├── kustomization.yaml
    └── replicas-patch.yaml
```

Let's take a look at our `base` directory. It contains our YAML manifests, they
are just Kubernetes manifests, nothing more, a `Deployment`, a `Service` and
an `HorizontalPodAutoscaler`.

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: helloworld
  labels:
    app: helloworld
spec:
  revisionHistoryLimit: 2
  selector:
    matchLabels:
      app: helloworld
  template:
    metadata:
      labels:
        app: helloworld
    spec:
      containers:
      - name: helloworld
        image: particule/helloworld
        imagePullPolicy: Always
        ports:
        - name: web
          containerPort: 80
apiVersion: autoscaling/v2beta1
kind: HorizontalPodAutoscaler
metadata:
  name: helloworld
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: helloworld
  minReplicas: 1
  maxReplicas: 2
  metrics:
  - type: Resource
    resource:
      name: cpu
      targetAverageUtilization: 60
---
apiVersion: v1
kind: Service
metadata:
  name: helloworld
spec:
  ports:
  - port: 80
  selector:
    app: helloworld
  type: NodePort
```

You can notice that our resources don't specify a `namespace`. Those "base"
manifests will never be deployed as is. They will serve as foundation for
futurs deployments, each one of them in their own `namespace`. Furthermore, our
base directory contains a `kustomization.yaml` file with all our YAML files
handled by Kustomize:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- helloworld-de.yaml
- helloworld-svc.yaml
- helloworld-hpa.yaml
```

Our next goal is to auto-generate YAML manifests for our two environments,
preprod and prod. Let's begin with `preprod`.

In our `preprod` directory, we have only one file `kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
bases:
- ../base/
namespace: preprod
namePrefix: preprod-
```

What does that mean ? First, we are going to load every manifests
from `base` directory. Then we are going to *patch* the namespace of those
manifests, and finally we will prefix our resources name with `preprod-`.

As said earlier, Kustomize is integrated with `kubectl`, you don't need a
third-party tool.

```yaml
$ kubectl kustomize preprod

apiVersion: v1
kind: Service
metadata:
  name: preprod-helloworld
  namespace: preprod
spec:
  ports:
  - port: 80
  selector:
    app: helloworld
  type: NodePort
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: helloworld
  name: preprod-helloworld
  namespace: preprod
spec:
  revisionHistoryLimit: 2
  selector:
    matchLabels:
      app: helloworld
  template:
    metadata:
      labels:
        app: helloworld
    spec:
      containers:
      - image: particule/helloworld
        imagePullPolicy: Always
        name: helloworld
        ports:
        - containerPort: 80
          name: web
---
apiVersion: autoscaling/v2beta1
kind: HorizontalPodAutoscaler
metadata:
  name: preprod-helloworld
  namespace: preprod
spec:
  maxReplicas: 2
  metrics:
  - resource:
      name: cpu
      targetAverageUtilization: 60
    type: Resource
  minReplicas: 1
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: preprod-helloworld
```

You can easily see the differences between `base` and `preprod`."

We can now do the same with `prod` with a new directory and a new
`kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
bases:
- ../base/
namespace: prod
namePrefix: prod-
patchesStrategicMerge:
- replicas-patch.yaml
```

Same as `preprod`, we change the namespace and add a prefix to our resources
names. But as our production deployment, we are going to patch our
`HorizontalPodAutoscaler`. By default, it has a minimum of 1 replica (you can
see this default value in the `base` directory). In production we want it to be
set, a minimum, at 2 and, a maximum, at 4.

`replicas-patch.yaml`:

```yaml
---
apiVersion: autoscaling/v2beta1
kind: HorizontalPodAutoscaler
metadata:
  name: helloworld
spec:
  minReplicas: 2
  maxReplicas: 4
```

It's just a patch, you don't need to redefine every spec, just the ones you
want to change.

After generation:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: prod-helloworld
  namespace: prod
spec:
  ports:
  - port: 80
  selector:
    app: helloworld
  type: NodePort
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: helloworld
  name: prod-helloworld
  namespace: prod
spec:
  revisionHistoryLimit: 2
  selector:
    matchLabels:
      app: helloworld
  template:
    metadata:
      labels:
        app: helloworld
    spec:
      containers:
      - image: particule/helloworld
        imagePullPolicy: Always
        name: helloworld
        ports:
        - containerPort: 80
          name: web
---
apiVersion: autoscaling/v2beta1
kind: HorizontalPodAutoscaler
metadata:
  name: prod-helloworld
  namespace: prod
spec:
  maxReplicas: 4
  metrics:
  - resource:
      name: cpu
      targetAverageUtilization: 60
    type: Resource
  minReplicas: 2
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: prod-helloworld
```

Our `maxReplicas` and `minReplicas` values have been correctly updated.

We can now apply our two environments:

```console
kubectl apply -k prod/
service/prod-helloworld created
deployment.apps/prod-helloworld created
horizontalpodautoscaler.autoscaling/prod-helloworld created

kubectl apply -k preprod/
service/preprod-helloworld created
deployment.apps/preprod-helloworld created
horizontalpodautoscaler.autoscaling/preprod-helloworld created
```

Let's check it out:

```console
kubectl -n preprod get hpa,deployments,services

NAME                                                     REFERENCE                       TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/preprod-helloworld   Deployment/preprod-helloworld   <unknown>/60%   1         2         1          38m

NAME                                 READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/preprod-helloworld   1/1     1            1           38m

NAME                         TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
service/preprod-helloworld   NodePort   10.103.2.95   <none>        80:30339/TCP   38m
```

```console
kubectl -n prod get hpa,deployments,services

NAME                                                  REFERENCE                    TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/prod-helloworld   Deployment/prod-helloworld   <unknown>/60%   2         4         2          36m

NAME                              READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prod-helloworld   2/2     2            2           36m

NAME                      TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
service/prod-helloworld   NodePort   10.107.91.161   <none>        80:31145/TCP   36m
```

Kustomize allows you to easily override YAML manifests without any templating
knowledge. [To go further](https://kubectl.docs.kubernetes.io/pages/reference/kustomize.html).

### Deploy Kustomize template with Flux CD

Kustomize is very handy to generate YAML manifests, but applying them with
`kubectl` is not something you want to do if you to stick with the GitOps
way.

We've been talking about [Flux CD](https://fluxcd.io/) for some time now,
espcially [here](https://particule.io/blog/cicd-concourse-flux/) and
[there](https://particule.io/blog/weave-flux-cncf-incubation/). Today we will
see how to make Flux and Kustomize work together.

Theoretically, Flux can work with, almost, [every templating tools we talked
about](https://docs.fluxcd.io/en/1.19.0/references/fluxyaml-config-files/#generator-configuration).
But we are going to, once again, focus on Kustomize. After all this is what
this article is about.

Let's start from our previous works and create a new directory
[`kustomize-flux`](https://github.com/particuleio/gitops-demo/tree/master/kustomize-flux)
based on our `kustomize` directory.

The structure is as follow:

```console
.
├── .flux.yaml
├── base
│   ├── helloworld-de.yaml
│   ├── helloworld-hpa.yaml
│   ├── helloworld-svc.yaml
│   └── kustomization.yaml
├── preprod
│   ├── flux-patch.yaml
│   └── kustomization.yaml
├── prod
│   ├── flux-patch.yaml
│   ├── kustomization.yaml
│   └── replicas-patch.yaml
├── values-flux-preprod.yaml
└── values-flux-prod.yaml
```

What's new ?

#### Flux deployment

First, we have two `values` Helm files which will help us to
deploy two Flux instances into our cluster. Yes we use Helm to deploy Flux.

* `flux-preprod`

```yaml
git:
  pollInterval: 1m
  url: ssh://git@github.com/particuleio/gitops-demo.git
  branch: master
  path: kustomize-flux/preprod
syncGarbageCollection:
  enabled: true
manifestGeneration: true
additionalArgs:
-  --git-sync-tag=flux-sync-prod
```

This instance handles the `preprod` directory.

* `flux-prod`

```yaml
git:
  pollInterval: 1m
  url: ssh://git@github.com/particuleio/gitops-demo.git
  branch: master
  path: kustomize-flux/prod
syncGarbageCollection:
  enabled: true
manifestGeneration: true
additionalArgs:
-  --git-sync-tag=flux-sync-prod
```

This instance handles the `prod` directory.

We can deploy our two Flux instances with the following commands:

```console
helm upgrade -i flux-prod fluxcd/flux --namespace prod --values values-flux-prod.yaml

helm upgrade -i flux-preprod fluxcd/flux --namespace preprod --values values-flux-preprod.yaml
```

```console
kubectl -n prod get pods
NAME                                   READY   STATUS    RESTARTS   AGE
flux-prod-588b66bb64-fsw5q             1/1     Running   0          31m
flux-prod-memcached-546c87f4d4-8rwtw   1/1     Running   0          34m
```

```console
kubectl -n preprod get pods
NAME                                      READY   STATUS    RESTARTS   AGE
flux-preprod-6bdc5dfb6-thqx9              1/1     Running   0          32m
flux-preprod-memcached-59f5454c6f-ldl25   1/1     Running   0          34m
```

#### `.flux.yaml`

This file is important, it will tell Flux how to generate our manifests.

```yaml
version: 1
patchUpdated:
  generators:
    - command: kubectl kustomize .
  patchFile: flux-patch.yaml
```

We use the same command we used to manualy generate our manifests.

Furthermore, we tell Flux where to find the Flux specific patches. Those
include the annotations Flux would use to automatically deploy a new release.

#### `flux-patch.yaml`

We already talked about [Flux](https://particule.io/blog/cicd-concourse-flux/)
so you already know that Flux can apply YAML files to your cluster but it can
also deploy new Docker images based on rules and filter such as
[`semver`](https://semver.org/).

This feature is handled with annotations on the `deployment`. Those can be
different for each environment, you might want to forbid an automatic
deployment in production but allow it in preprod.

For example, the file `flux-patch.yaml` in production:

* `prod/flux.yaml`

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    flux.weave.works/locked: "true"
    flux.weave.works/locked_msg: Lock deployment in production
    flux.weave.works/locked_user: Particule
  name: prod-helloworld
  namespace: prod
```

But in `preprod` we will automatically deploy every `1.x.x` releases.

* `preprod/flux-patch.yaml`

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    flux.weave.works/automated: "true"
    flux.weave.works/tag.helloworld: semver:~1
  name: preprod-helloworld
  namespace: preprod
```

Once everything is ready in our git repository, we can activate Flux for this
git repository and allow Flux to pull/push from/to it. To achieve that, you
just need to fetch de public key of each Flux instances and add it on your
GitHub account (*Settings -> Deploy Keys*).

```console
kubectl -n preprod logs flux-pod | head

ts=2020-06-10T14:35:43.197547567Z caller=main.go:493 component=cluster identity.pub="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDNYjo5gddG6fXJg75L3gf2mXNBV+DKd9LPz9ZqK2phhwD0fI7J2LajxKnTQGtxj72VBqU+lweEP8YV15auswyjraIYLgnLEE5POb6H8Cjz0vfVX61j3fcLnH77n48GQDKWo0rYQ9hxSmSthi/E1FGy41thxOYRm/IIErN8whKC0+YWDeKlwLNZatSSs/3XA4Q3eCpdPWwAot8sEWDOexUeno/GyaDhBiHm7gxjKkMPsnW8lj9ovtCzjt2H+vLV57neIcx4hx/bhWr3z+wVxkbnDv8zIfXaziXfy5Ueuz0e9sQ3pE1lbrTkeumQN0ekHNAdRjpIa89RRok6KTfBFN7w8iXoLvuSR1NZe9/aunZwqG0ZDGXQjmE8/AHy00QhXmDQT+1VJX00uq/0Jx87v6yiHV+I3LyA1Rn946S4qpxsvFAqDVyKrxFy6WwDSDhd4GHAlI/gFE6dPn8FXqQtL9NVWUxTqFs6svHTLNq6orQ92oKELcsTPHvUyvflj+5JW6k= root@flux-preprod-865d6d9666-6w4x7"
```

Once your keys are added, Flux will start deploying resources with Kustomize.

```console
kubectl -n preprod logs -f flux-pod

ts=2020-06-10T14:11:29.602531682Z caller=sync.go:539 method=Sync cmd=apply args= count=3
ts=2020-06-10T14:11:29.98907821Z caller=sync.go:605 method=Sync cmd="kubectl apply -f -" took=386.489628ms err=null output="service/preprod-helloworld unchanged\ndeployment.apps/preprod-helloworld unchanged\nhorizontalpodautoscaler.autoscaling/preprod-helloworld unchanged"
```

```console
kubectl -n preprod logs -f flux-pod

ts=2020-06-10T14:13:58.283012811Z caller=sync.go:539 method=Sync cmd=apply args= count=3
ts=2020-06-10T14:13:58.684738069Z caller=sync.go:605 method=Sync cmd="kubectl apply -f -" took=401.666475ms err=null output="service/prod-helloworld unchanged\ndeployment.apps/prod-helloworld unchanged\nhorizontalpodautoscaler.autoscaling/prod-helloworld unchanged"
```

Our resources are correctly applied into our cluster with Flux.

#### Auto-deployment test

We are going to push a new image to the Docker Registry, the `1.1`, and we will
see what Flux are going to do with it.

```console
docker push particule/helloworld:1.1
```

Flux polls the Docker Registry every 5 minutes. Flux will detect the new image
and will update our git repository :

![](/images/flux/flux-update.png#center)

#### Workflow in action

What's really happening in the cluster ? Here's the Flux's workflow deployment
for the initial deployment:

* Flux generates YAML manifests with Kustomize
* Flux applies the `flux-patch.yaml` files
* Flux applies the manifests into the cluster

For a Docker image update:

* Flux scans the Docker Registry
* Flux detects the new image
* Flux updates the corresponding `flux-patch.yaml` file and push it to the git repository
* Flux met à jour sur le dépôt git le fichier `flux-patch.yaml` correspondant
* The initial workflow apply

#### To go further

This article is inspired by the
[Flux community](https://github.com/fluxcd/flux-kustomize-example) which
provides git repository as examples to easily deploy manifests with Kustomize.

[The official documentation for this feature is also available.](https://docs.fluxcd.io/en/latest/references/fluxyaml-config-files/)

### Conclusion

We already talked about Flux many times. It's a simple tool full of features
that can acheive great things with a small amout of times.

Flux can centralize your Kubernetes manifests and use a GitOps workflow while
keeping flexibility with your templating tools.

* [**Kevin Lefevre**](https://www.linkedin.com/in/kevinlefevre/)
* [**Romain Guichard**](https://www.linkedin.com/in/romainguichard/)
