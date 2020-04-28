---
Title: Canary deployment with Argo
Date: 2020-04-28
Category: Kubernetes
Summary: Introduction to ArgoCD and Argo-Rollout, Canary Deployment, rollback, everything *as code* !
Author: Romain Guichard
image: images/argo/argo-logo.png
lang: en
---

Once again, we are going to talk about GitOps... In [our last
article](https://particule.io/blog/cncf-argo/), we briefly talked about Argo
and [its adoption by the CNCF](https://www.cncf.io/projects/). As a reminder,
Argo is a Continuous Delivery tools suite:

- ArgoCD
- Argo Workflow
- Argo Rollout
- Argo Event

I would advise you to read or read again our article:

<https://particule.io/en/blog/cncf-argo/>

Introductions have been made, we are now going to practice with ArgoCD and Argo
Rollout making a full application deployment with a simple git commit. We will
see how Argo Rollout allows us to make Canary deployment, watch and control the
rolling update and be able to rollback if something wrong happen.

### Our application and its releases

I will use a simple application which provides a webservice with a json output
like this:

```
{
  "color": "red",
  "status": "ok"
}
```

Very simple. We will watch `color` to track application upgrades and `status`
as a health metric.

Here's three releases of our application:

- `1.0` with `color` at `red`
- `2.0` with `color` at `blue`
- `3.0` with `color` at `black` and `status` at `nok`


```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: colorapi
  labels:
    app: colorapi
spec:
  replicas: 5
  revisionHistoryLimit: 2
  selector:
    matchLabels:
      app: colorapi
  template:
    metadata:
      labels:
        app: colorapi
    spec:
      containers:
      - name: colorapi
        image: particule/simplecolorapi:1.0
        imagePullPolicy: Always
        ports:
        - name: web
          containerPort: 5000
---
apiVersion: v1
kind: Service
metadata:
  name: colorapi
spec:
  ports:
  - port: 80
  selector:
    app: colorapi
  type: LoadBalancer
```


### ArgoCD

As hinted by its name, ArgoCD handles the Continuous Delivery part, it allows
us to deploy specific versions and keep our actual deployments synced with the
desired state stored in a git repository. ArgoCD supports
[Helm](https://helm.sh/), [Ksonnet](https://ksonnet.io/),
[Jsonnet](https://jsonnet.org/), [Kustomize](https://kustomize.io/) and of
course standalone Kubernetes manifests. We will use the laters for this
article.

I let you walk through the
[official "getting started" guide](https://argoproj.github.io/argo-cd/getting_started/)
to deploy Argo on your Kubernetes cluster. You should also install the ArgoCD
CLI. Then we can start deploying our first application.

```console
$ argocd app create colorapi --repo https://github.com/particuleio/demo-concourse-flux.git --path deploy --dest-server https://kubernetes.default.svc --dest-namespace default
$ argocd app sync colorapi
$ kubectl get pod
NAME                          READY   STATUS    RESTARTS   AGE
colorapi-7ccb9d965b-8pr54   1/1     Running   0          22s
colorapi-7ccb9d965b-9vtmp   1/1     Running   0          22s
colorapi-7ccb9d965b-c7jkf   1/1     Running   0          22s
colorapi-7ccb9d965b-klt7q   1/1     Running   0          22s
colorapi-7ccb9d965b-s2ftc   1/1     Running   0          22s
```

Our first test will be a modification of our replicas count. We are going to
change that parameter in our Deployment, commit/push our code and see if ArgoCD
updates our actual Deployment. ArgoCD can track either a tag, a commit or
a branch. If you track a git tag, don't forget to update it to the latest
commit.

<https://argoproj.github.io/argo-cd/user-guide/tracking_strategies/>

A poll occurs every 3 minutes, it shouldn't take long before the scheduling of
our new replicas.

This is something pretty simple, in fact, we already describe and talk about
such behaviour [when we introduced you to Flux CD](https://particule.io/blog/cicd-concourse-flux/).
They do the same thing. However, Flux can track a Docker image and update your
Deployment manifest. ArgoCD can't at the moment.


Let's do a real application update.

### Argo Rollout

Next component of the suite: [Argo
Rollout](https://github.com/argoproj/argo-rollouts). It improves rolling update
strategies provided by Kubernetes and adds the **Canary Deployment** and
**Blue/Green Deployment**. The Canary is the one we will demonstrate. There is
no exact definition of a Canary Deployment. The concept is to redirect a small part
of the application traffic to the new version of the application. After that,
it's free for all, you can rapidly scale the new version up and replace the old
one or you can do it steadily but slowly. The one commun point is to run tests
and diagnosis to make sure that the new version doesn't bring any sort of
regression.

Let's deploy Argo Rollout:

```console
$ kubectl create namespace argo-rollouts
$ kubectl apply -n argo-rollouts -f https://raw.githubusercontent.com/argoproj/argo-rollouts/stable/manifests/install.yaml
```

Argo Rollout brings a CustomResourceDefinition that will superset the
Deployment ressource: **Rollout**. Turning a Deployment into a Rollout is easy,
you just have to change some fields:

```
apiVersion: argoproj.io/v1alpha1 # Changed from apps/v1
kind: Rollout # Changed from Deployment
```

Commit and push your Rollout. ArgoCD shouldn't do anything because it's
basically the same resource.

#### Rollout strategy

Rollout resource allows to improve the `strategy` Deployment spec. Here, we can
define our Canary configuration.

```yaml
  strategy:
    canary:
      steps:
      - setWeight: 20
      - pause:
          duration: "30s"
      - setWeight: 50
      - pause:
          duration: "30s"
```

There will be 4 steps:

- We redirect 20% of the traffic to our new version
- We wait 30 seconds
- We redirect 50% of the traffic to our new version
- We wait 30 seconds

The last step, which is implicite, redirects 100% of the traffic to the new
version, ending the rolling update.

Only an Ingress can really redirect traffic between many services. We only have
one Service, so the "redirection" is actually made by the proportion of pods
running by different ReplicaSet at a given time and a round-robin mechanism.
Argo Rollout can, however, work with real [traffic management, Istio,
Nginx et ALB are
supported](https://argoproj.github.io/argo-rollouts/features/traffic-management/).

Let's update our Rollout with a new image tag:

```console
$ sed -i 's/1.0/2.0/g' deploy/helloworld.yml
$ git commit -am "bump: 2.0"
$ git push
$ argocd app sync colorapi
TIMESTAMP                  GROUP              KIND         NAMESPACE                  NAME    STATUS    HEALTH        HOOK  MESSAGE
2020-04-25T11:40:32+02:00  argoproj.io     Rollout           default              colorapi    Synced   Healthy
2020-04-25T11:40:32+02:00                  Service           default              colorapi    Synced   Healthy
2020-04-25T11:40:32+02:00  argoproj.io  AnalysisTemplate     default              webcheck  OutOfSync

Name:               colorapi
Project:            default
Server:             https://kubernetes.default.svc
Namespace:          default
URL:                https://argo_url.tld/applications/colorapi
Repo:               https://github.com/particuleio/demo-concourse-flux
Target:             argocd
Path:               deploy
SyncWindow:         Sync Allowed
Sync Policy:        Automated (Prune)
Sync Status:        OutOfSync from argocd (95662aa)
Health Status:      Healthy

Phase:              Running
Start:              2020-04-25 11:40:34 +0200 CEST
Finished:           <nil>
Duration:           1s

GROUP        KIND              NAMESPACE  NAME      STATUS     HEALTH   HOOK  MESSAGE
             Service           default    colorapi  Synced     Healthy
argoproj.io  AnalysisTemplate  default    webcheck  OutOfSync
argoproj.io  Rollout           default    colorapi  Synced     Healthy
```

Here's what should happen:

- A new ReplicaSet (RS) is created with 2 desired pods. There are 2 canary pods
  out of 8 16% ~= 20%)
- 30 sec wait
- A new canary pod is created and three basline pods are terminating, there are
  3 canary pods out of 6 (50%)
- 30 sec wait
- The last 3 baseline pods are terminating and three new canary pods appear,
  ending the rolling update


If we curl our application, we can see this behaviour:

```console
$ while true; do curl $monapp | jq .color; sleep 0.5; done
"red"
"red"
"red"
"red"
"red"
"red"
"red"
# début des 20%
"blue"
"red"
"red"
"red"
"red"
"red"
"blue"
"red"
"red"
"red"
"blue"
"blue"
"red"
"red"
"red"
"red"
"red"
"red"
"red"
# début des 50%
"blue"
"red"
"blue"
"red"
"red"
"blue"
"blue"
"blue"
"red"
"blue"
"red"
"blue"
"blue"
"red"
"red"
"blue"
"blue"
"red"
"red"
# Fin du rolling update
"blue"
"blue"
"blue"
"blue"
"blue"
"blue"
"blue"
```

This rolling-update can also be started with your console and the [argo plugin for
kubectl](https://argoproj.github.io/argo-rollouts/features/kubectl-plugin/).

```console
$ kubectl argo rollouts set image colorapi "*=particule/simplecolorapi:2.0"
rollout "colorapi" image updated
```

This plugin also offers this good looking interface to follow your
rolling-update:

```console
$ kubectl argo rollouts get rollout colorapi -w
Name:            colorapi
Namespace:       default
Status:          ✔ Healthy
Strategy:        Canary
  Step:          4/4
  SetWeight:     100
  ActualWeight:  100
Images:          particule/simplecolorapi:1.0 (stable)
Replicas:
  Desired:       3
  Current:       3
  Updated:       3
  Ready:         3
  Available:     3

NAME                                  KIND         STATUS        AGE    INFO
⟳ colorapi                            Rollout      ✔ Healthy     5h52m
├──# revision:32
│  ├──⧉ colorapi-66f9756599           ReplicaSet   ✔ Healthy     10m    stable
│  │  ├──□ colorapi-66f9756599-p4kfl  Pod          ✔ Running     4m6s   ready:1/1
│  │  ├──□ colorapi-66f9756599-lqnsn  Pod          ✔ Running     3m32s  ready:1/1
│  │  └──□ colorapi-66f9756599-554wc  Pod          ✔ Running     2m58s  ready:1/1
│  └──α colorapi-66f9756599-32        AnalysisRun  ✔ Successful  4m6s   ✔ 30,⚠ 12
├──# revision:31
│  ├──⧉ colorapi-7d458c8cd8           ReplicaSet   • ScaledDown  5m36s
│  └──α colorapi-7d458c8cd8-31        AnalysisRun  ✔ Successful  5m36s  ✔ 30
├──# revision:30
   ├──⧉ colorapi-59b5ddb84f           ReplicaSet   • ScaledDown  7m1s
   └──α colorapi-59b5ddb84f-30        AnalysisRun  ✔ Successful  7m     ✔ 30
```

#### Analysis Run

But what's very interesting with Argo Rollout (and every canary deployment
tools) is the ability to watch your rolling update and the ability to take
actions based on some metrics. If those metrics don't match with what was
expected, an automatic rollback occures.

We use a new resource for that: `AnalysisRun`. Let's describe it with the piece
of code you need to change in your Rollout manifest.

```yaml
strategy:
    canary:
      analysis:
        templates:
        - templateName: webcheck
      args:
      - name host
        value: colorapi
      steps:
      - setWeight: 20
      - pause:
          duration: "30s"
      - setWeight: 50
      - pause:
          duration: "30s"
---
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: webcheck
spec:
  args:
  - name: host
  metrics:
  - name: webcheck
    failureLimit: 1
    interval: 5
    successCondition: result == "ok"
    provider:
      web:
        # paceholders are resolved when an AnalysisRun is created
        url: "http://{{args.host}}/"
        jsonPath: "{$.status}"
```

Some inputs. Let's start with the changes in our `Rollout`. We introduced the
`analysis` parameter, it allows to specify the AnalysisTemplate we will use.
This analysis will run indefinitely, it will only be stopped when it will fail
or when our rolling update will be completed. We also pass some arguments to be
used later.

The `Analysis` now. There are many
[providers](https://argoproj.github.io/argo-rollouts/features/analysis/) and
we chose `web` because it allows us to easily base on our application json
output to determine the outcome of your analysis. Our test is simple, we are
going to check the value of `status`, if it's "ok", it's good, otherwise, the
test would be marked as failed. The test will occur every 5 seconds and we
tolerate one failure before initiate a rollback.

Demonstration with the non functionnal image.

```console
$ kubectl argo rollouts set image colorapi "*=particule/simplecolorapi:3.0"
rollout "colorapi" image updated

$ while true; do curl $monapp | jq .color; sleep 0.5; done
# Beginning of the test
"red"
"red"
"red"
"red"
"red"
"red"
"red"
# 20%, trouble's coming
"black"
"red"
"red"
"black"
"red"
"black"
"red"
"red"
"red"
"red"
"red"
"black"
"black"
# More than 1 error happened, rollback initiated
"red"
"red"
"red"
"red"
"red"
"red"
"red"
"red"
"
```

The result of our Rollback would look like this:

```console
$ kubectl argo rollouts get rollout colorapi
Name:            colorapi
Namespace:       default
Status:          ✖ Degraded
Strategy:        Canary
  Step:          0/2
  SetWeight:     0
  ActualWeight:  0
Images:          particule/simplecolorapi:1.0 (stable)
Replicas:
  Desired:       3
  Current:       3
  Updated:       0
  Ready:         3
  Available:     3

NAME                                            KIND         STATUS        AGE  INFO
⟳ colorapi                                      Rollout      ✖ Degraded    30h
├──# revision:34
│  ├──⧉ colorapi-7d458c8cd8                     ReplicaSet   • ScaledDown  28h  canary
│  └──α colorapi-7d458c8cd8-34                  AnalysisRun  ✖ Failed      35m  ✔ 1,✖ 2

```

Our state is `Degraded` because we asked for the `3.0` image but it failed. We
can have our `Healthy` state back by asking again the `1.0`.

What matters is that our rolling update was successfully stopped. We prevented a
non functionnal image from being deployed in production !

### Conclusion

We just scratched the surface of what Argo can offer. Our metric didn't make
much sense, neither did our application but this example was sufficient enough to
understand the importance of GitOps concepts.


[**Romain Guichard**](https://www.linkedin.com/in/romainguichard)
