---
Title: Multi git branches workflow with Concourse-CI
Date: 2018-03-13T11:00:00+00:00
Category: CI/CD
Summary: Build every git project's branches so that every developers can see their changes ! Once again with Concourse-CI !
Author: Romain Guichard
image: images/thumbnails/cicd-generic.png
lang: en
---

### Introduction

I like Concourse, it is, IMO, one of the best CI tool I had the opportunity to work with. The worker system can easily scale, nothing is stored _directly_ in Concourse and the yaml syntax used to describe the pipelines is exactly what we can expect in 2018. Nevertheless, [one of the main concerns the Concourse community has is the absence of git branch management](https://github.com/concourse/concourse/issues/1172). When you declare a git resource, you have to specify the branch you want to checkout. If I create a new feature branch, I have to create a new pipeline for my branch... It's time consumming, it will not scale and you increase the likelihood of not having that kind of permission... Who said automation ?

Don't worry though : if Concourse doesn't handle it natively, it allows us to create any custom resource. And that gives us all we need !


We will take a simple usecase into account. We want to build every feature branches so each developer can see a preview of their work without having to build it locally. In a continuous delivery approach, we'd like to build each Pull Request (given that we work with GitHub) so someone can quickly decide if the build result is OK. [A custom resource can do this job](https://github.com/jtarchie/github-pullrequest-resource) but we will not use it.


As in my [previous post](https://blog.osones.com/en/building-a-continious-deployment-pipeline-with-kubernetes-and-concourse-ci.html), I will use [Kubernetes](https://kubernetes.io/) as my container orchestration engine. For the record, Kubernetes is deployed with [kubeadm](https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/) (v1.9.3) and Concourse-CI with Docker containers (scheduled on the Kubernetes cluster of course) with [those images](https://hub.docker.com/r/concourse/concourse/) (v3.9.2). We will use Ingress resource to redirect the trafic to each pod based on the host http header.

We'll use this custom resource :

* https://github.com/vito/git-branches-resource

All clear?

Let's go!

### Prep talk

First things first, we'll need some tools:

* A public GitHub repository
* A DockerHub account
* Kubernetes credentials


The demo application will be this one:
[https://github.com/osones/demo-cicd](https://github.com/osones/demo-cicd) (same as in my previous blog post, yes ^^)

It's - intentionally - extremely simple : printing our logo and a "hello world". It almost comes entirely from the [dockercloud's hello-world](https://hub.docker.com/r/dockercloud/hello-world/).

We are set, let's start with Concourse.

### Concourse-CI

[Concourse CI](/images/concourse-logo.png#center)

So we want to build every branches. Two options, one pipeline with one git resource per branch. It seems complicated to maintain so we'll choose to have one pipeline per branch. Those pipelines need to be deployed each time a new branch is detected and to avoid stacking pipelines, we'll need to remove pipelines refering to deleted branches. This job will be handle by one pipeline (let's call it "master pipeline"
).

Our pipeline will look like the following.

```yaml
resource_types:
- name: git-branches
  type: docker-image
  source:
    repository: vito/git-branches-resource

resources:
  - name: demo
    type: git-branches
    source:
      uri: git@github.com:osones/demo
jobs:
  - name: "Create pipelines"
    public: false
    plan:
      - get: demo
        trigger: true
      - task: Create pipelines
        file: demo/create-pipeline.yml
```

Nothing special here.

Let's see our `create-pipeline.yml̀`

```yaml
---

platform: linux

image_resource:
  type: docker-image
  source:
    repository: rguichard/fly
    tag: latest
inputs:
  - name: branches
outputs:
  - name: output
run:
  path: git/create-pipeline.sh
```

The baseimage used is just an alpine linux image with the fly cli installed.

and the shell script :

```bash
#!/bin/bash

export NEW_VERSIONS=$(cat branches/branches)
export OLD_VERSIONS=$(cat branches/removed)

fly login -t your-concourse -c https://ci.osones.com -u concourse -p mysuperpassword

for version in $NEW_VERSIONS; do
  sed "s/___BRANCH___/$version/g" demo/.ci/pipeline-demo.tmpl > demo/.ci/pipeline-app.result
  echo "Create pipeline branch $version"
  fly -t your-concourse sp -n -p app-$version -c demo/.ci/pipeline-app.result
  echo "Unpause pipeline branch $version"
  fly -t your-concourse up -p app-$version
done

for version in $OLD_VERSIONS; do
  echo "Delete pipeline branch $version"
  fly -t your-concourse dp -n -p app-$version
done
```

As you can see, our shell script has a plain text password... You have a choice to make: either you make your git repository private or you use [Vault](https://www.vaultproject.io/) to [encrypt sensitive information](https://concourse.ci/creds.html#vault). I chose to use a private repository, so much faster to put in place...


The trick is to use the list of branches generated by our git-branches resource. The resource generates three files, on with all branches, one with the ones newly created and one with the deleted ones. To be sure pipeline of _existing_ branches will be updated (if necessary), we choose to apply (or re-apply) the pipeline for every branches, not just the new ones.

The pipeline template will, obviously, differ, based on your application. Mine looks like that :

```yaml
resource_types:
- name: kubernetes
  type: docker-image
  source:
    repository: zlabjp/kubernetes-resource
    tag: "1.9"

resources:
  - name: git-app
    type: git
    source:
      uri: git@github.com:osones/demo
      branch: ___BRANCH___
  - name: docker-demo
    type: docker-image
    source:
      repository: rguichard/osones-blog
      username: rguichard
      password: {{dockerhub-passwd}}
      tag: ___BRANCH___
  - name: k8s
    type: kubernetes
    source:
      kubeconfig: {{k8s_server}}
jobs:
  - name: "Docker Build"
    public: false
    plan:
      - get: git-app
        trigger: true
      - task: Update version
        file: git-app/update-version.yml
        params:
          BRANCH_NAME: ___BRANCH___
      - put: docker-demo
        params:
          build: output
          tag: output/branch
  - name: "Deploy"
    public: false
    plan:
      - get: git-app
      - get: docker-demo
        trigger: true
        passed:
          - "Docker Build"
      - task: Generate k8s resources
        file: git-app/generate-manifest.yml
      - put: k8s
        params:
          kubectl: apply -f output/manifest.yml
          wait_until_ready: 300
  - name: "Rolling update"
    public: false
    plan:
      - get: k8s
        trigger: true
        passed:
          - "Deploy"
      - put: k8s
        params:
          kubectl: delete pods -l app=app-___BRANCH___ -n default
          wait_until_ready: 300
```


Yeah it looks like a lot to the one in my previous article ^^

We choose, for each branch, to build a Docker image which will contain the source code of our demo app. It's not ideal to put data inside a Docker image, but it's pretty useful in that case. I'm not showing you the shell script behind, it's pretty straightforward, it mainly replaces the "\_\_\_VERSION\_\_\_" with the actual version/branch.

Why did I use the same Kubernetes resource twice ? The job __Deploy__ is for deploying the application the first time the branch is created. But as the template will not change (image stays unchanged), this job will not do anything after the first deployment. So we use a second job __Rolling Update__ which will delete our pod and wait for our deployment to schedule a new one (don't forget the `imagePullPolicy: Always`).

Just a quick view of our Concourse with our blog as a demonstrator :

![Pipelines](/images/concourse-pipelines-branches.png#center)

In our Kubernetes manifest template, we use the same trick with \_\_\_VERSION\_\_\_ to create custom Kubernetes objects. Therefore, we can have a Ingress resource for each branch et access it through its own URL !


**[Romain Guichard](https://fr.linkedin.com/in/romainguichard/en)**
