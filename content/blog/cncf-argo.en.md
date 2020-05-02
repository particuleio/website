---
Title: CNCF adopts Argo
Date: 2020-05-02
Category: Kubernetes
Summary: CNCF adopts Argo inside [incubator](https://www.cncf.io/projects/)
Author: Kevin Lefevre
image: images/argo/argo-logo.png
lang: en
---

### Let's continue to talk about Gitops

What is Gitops ? We already talked a little bit about it [here](https://particule.io/en/blog/cicd-concourse-flux/) and [there](https://particule.io/en/blog/flux-semver/), especially with [FluxCD](https://particule.io/en/blog/weave-flux-cncf-incubation/) for the technical part.

Gitops is a collection of tools and best practices in continuity with the DevOps movement which allows you to manage your infrastructures and applications with Git as a source of truth and center of operations. To do so, we need 3 essential components:

* a code depot
* a place to deploy
* some glue to realise some actions between the content of the code depot and the place where we want to deploy

This glue is often split between two categories:

* Build : Continuous Integration
* Deployment : Continuous Delivery

Several tools exist such as [Jenkins](https://jenkins.io/), [Gitlab](https://docs.gitlab.com/ee/ci/), or [Travis](https://travis-ci.com/). There are also specific tools dedicated to the CD part like [Spinnaker](https://www.spinnaker.io/), Weave [Flagger](https://github.com/weaveworks/flagger) and [Flux](https://www.weave.works/oss/flux/).

### Whats is [Argo](https://argoproj.github.io/) ?

Argo is a project which aims to unify the different steps of application delivery under a single platform and to do it [under the CNCF colors](https://www.cncf.io/blog/2020/04/07/toc-welcomes-argo-into-the-cncf-incubator/).

Like many projects inside the CNCF, Argo is build around extending Kubernetes functionalities.

Argo is split between sub projects, each one addressing a specific problematic.

#### [Argo Workflow](https://argoproj.github.io/projects/argo)

Native Kubernetes pipeline creation: Pods, jobs, etc as well as orchestration and artifacts handling which can be compare to a classic CI tools.

#### [Argo CD](https://argoproj.github.io/projects/argo-cd)

As hinted by its name, handles continuous delivery, allowing you to deploy specific application version and to reconcile the desired remote state with actual cluster state. Argo supports [Helm](https://helm.sh/), [Ksonnet](https://ksonnet.io/), [Jsonnet](https://jsonnet.org/) and [Kustomize](https://kustomize.io/) in addition of classic Kubernetes manifests.

![argo-cd](/images/argo/argocd_architecture.png#center)

#### [Argo Rollout](https://argoproj.github.io/argo-rollouts/)

Augments Kubernetes rolling update strategies by adding *Canary Deployments* and *Blue/Green Deployments*. [Check out our article here](https://particule.io/en/blog/argocd-canary/)

#### [Argo Event](https://argoproj.github.io/projects/argo-events)

Execute [actions](https://argoproj.github.io/argo-events/concepts/trigger/) that depends on [external events](https://argoproj.github.io/argo-events/concepts/event_source/). For example, to trigger an Argo Workflow pipeline after receiving an [AWS SNS](https://aws.amazon.com/fr/sns/) event.

![argo-event](/images/argo/argo-events-top-level.png#center)

### Project roadmap

Those projects are not alone on the market, Argo CD offers similar functionalities as [Flux CD](https://fluxcd.io/).

For the continuous delivery part, Argo CD and Flux now have a [common project](https://www.weave.works/blog/argo-flux-join-forces): Argo Flux which aim to merge the feature of both under one project.

This will add a feature we love in Flux which is the monitoring of Docker registries to automatically deploy new applications release based on [glob and/or semver](https://particule.io/en/blog/flux-semver/). This project will be a joined CNCF project.

Along the same lines, we may see [Weave Flagger and Argo Rollout getting closer](https://www.weave.works/blog/argo-flux-join-forces) as they both offer the same features.

**Kevin Lefevre**
