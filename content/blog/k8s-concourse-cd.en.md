---
Title: Building a continious deployment pipeline with Kubernetes and Concourse-CI
Date: 2018-02-11
Category: CI/CD
Summary: Kubernetes and Concourse-CI can be two great choices to build a continious deployment pipeline, from source code to production deployment
Author: Romain Guichard
image: images/thumbnails/kubernetes.png
lang: en
---

### Introduction

Building and deploying containerized services manually is slow and subject to errors. Continuous delivery with automated build and test mechanisms helps detect errors early, saves time, and reduces failures, making this a popular model for application deployments on your favorite containers orchestrator (if it's not Kubernetes yet, [Osones provides training](http://osones.com/formations/kubernetes.en.html), let us convince you!). This chain guarantees idempotency and reduces time between code development and production release.

In this blog post, we will use [Concourse-CI](https://concourse.ci/) as our CI/CD tool and [Kubernetes](https://kubernetes.io/) as a container orchestration engine. We will not talk about Concourse and Kubernetes deployment because it's out of the scope of this blog post, but for the record, Kubernetes is deployed with [kubeadm](https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/) (v1.9.2) and Concourse-CI with Docker containers (scheduled on the Kubernetes cluster of course) with [those images](https://hub.docker.com/r/concourse/concourse/) (v3.8.0).

The workflow will be as follow:

* Commit and push your code (on GitHub for example)
* Concourse will trigger the Docker image build and push it to a registry (DockerHub in our example)
* Concourse will deploy your application on Kubernetes
* Kubernetes will, finally, make your application reachable with differents kind of Kubernetes objects

To keep this example as simple as possible, there will be no test ran by Concourse. Of course, given the nature of your tests, you'll have to run them at some point.

All clear?

Let's go!

### Prep talk

First things first, we'll need some tools:

* A public GitHub repository
* A DockerHub account
* Kubernetes credentials

Let's create our git repository:
```bash
$ mkdir demo-cicd && cd demo-cicd
$ git init
$ git remote add origin https://github.com/osones/demo-cicd
$ touch README.md
$ git add README.md && git commit README.md -m "init"
$ git push -u origin
```

The demo application will be this one:
[https://github.com/osones/demo-cicd](https://github.com/osones/demo-cicd)

It's - intentionally - extremely simple, printing our logo and a "hello world". It almost comes entirely from the [dockercloud's hello-world](https://hub.docker.com/r/dockercloud/hello-world/).

We are set, let's start with Concourse.

### Concourse-CI

![Concourse CI](/images/concourse-logo.png#center)

As said before, I will not get into details regarding Concourse. To keep it short, Concourse is a CI/CD tool written in Go that scales natively and can be easily deployed on cloud platforms. It uses "resources", allowing you to get Docker images, push data on AWS S3, spin up Kubernetes pods etc. Everything is written in yaml files, making it easy to put all your configuration into another git repository.

Our pipeline will look like the following.

First, our resources:
```yaml
resource_types:
- name: kubernetes
  type: docker-image
  source:
    repository: zlabjp/kubernetes-resource
    tag: "1.9"

resources:
  - name: git-demo
    type: git
    source:
      uri: https://github.com/osones/demo-cicd
      branch: master
  - name: docker-demo
    type: docker-image
    source:
      repository: osones/demo-cicd
      username: rguichard
      password: {{dh-rguichard-passwd}}
  - name: k8s
    type: kubernetes
    source:
      kubeconfig: {{k8s_server}}
```
We use 3 resources:

* our GitHub repository (since we are going to checkout this repo unauthenticated, we will probably hit the API's rate limit but you can bypass this limit by providing your ssh private key to the git resource)
* our DockerHub image
* our Kubernetes cluster. This resource is not official and you can see I imported it at above the resources declaration.

And now, our jobs:

```yaml
jobs:
  - name: "Docker-Build"
    public: false
    plan:
      - get: git-demo
        trigger: true
      - put: docker-demo
        params:
          build: git-demo
  - name: "Deploy Application"
    public: false
    plan:
      - get: docker-demo
        trigger: true
        passed:
          - "Docker-Build"
      - put: k8s
        params:
          kubectl: delete pods -l app=demo-cicd
          wait_until_ready: 300
```
Only two jobs! The first one builds our image form the code source. As you can see, Concourse is pretty easy and powerful, only 6 lines for this job. The second job has to trigger a rolling update on Kubernetes if a new Docker image is detected.

As a rolling update strategy, we decided to simply kill our pods (thanks to the labels), our deployment object will take care to spin up as many replicas as we need with the new Docker image. It's clearly not the more efficient way to go but come on, it's just an example.

We can deploy it with the Fly CLI:
```bash
$ fly -t osones set-pipeline -p demo-cicd -c demo-cicd.yml --load-vars-from secrets/demo-cicd.yml
$ fly -t osones unpause-pipeline -p demo-cicd
```
Our `secrets/demo-cicd.yml` contains the variables used in our pipeline.

![Pipeline](/images/pipeline-concourse-k8s-cd.png#center)

And now, Kubernetes!

### Kubernetes

![Kubernetes](/images/docker/kubernetes.png#center)

We are going to use 3 Kubernetes objects for our application, a deployment, a service and an ingress. Our ingress controller we be implemented by Traefik. [Check out Kevin's blog post on Traefik as an Ingress Controller for Kubernetes for more infos](https://blog.osones.com/en/kubernetes-ingress-controller-with-traefik-and-lets-encrypt.html).

```yaml
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  namespace: default
  name: demo-cicd
  labels:
    app: demo-cicd
spec:
  replicas: 3
  revisionHistoryLimit: 2
  template:
    metadata:
      namespace: default
      labels:
        app: demo-cicd
    spec:
      containers:
        - name: demo-cicd
          image: osones/demo-cicd:latest
          imagePullPolicy: Always
---
apiVersion: v1
kind: Service
metadata:
  namespace: default
  name: demo-cicd-svc
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
  selector:
    app: demo-cicd
  type: ClusterIP
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  namespace: default
  name: demo-cicd
  annotations:
    kubernetes.io/ingress.class: traefik
spec:
  rules:
    - host: demo-cicd.osones.com
      http:
        paths:
          - backend:
              serviceName: demo-cicd-svc
              servicePort: 80
```
The `imagePullPolicy: Always` is pretty important because it tells Kubernetes to pull at each deployment. It ensures that the new Docker image will be deploy when a rolling update is triggered.

If you doubt yourself, you can see our 3 replicas:
```bash
$ kubectl get pods -l app=demo-cicd
ds -l app=demo-cicd
NAME                         READY     STATUS    RESTARTS   AGE
demo-cicd-58c9f4c994-9dbm7   1/1       Running   0          1m
demo-cicd-58c9f4c994-hxmnf   1/1       Running   0          1m
demo-cicd-58c9f4c994-q8tnh   1/1       Running   0          1m
```
And our web application is reachable at thr URL used in the ingress object.

![helloworld-red](/images/helloworld-osones-rouge.png#center)

Happily, we can also see that our web application is load-balanced between the 3 pods (mind your browser's cache ;) ).

Let's decide to change the color of our title!

```bash
$ sed -i s/red/green/ index.php
$ git commit -am "from red to green" && git push
```

Wait & see, wait & see... (maybe 3 minutes ^^)

![helloworld-green](/images/helloworld-osones-vert.png#center)

We keep this extremely simple. In the future we could :

* Use the `semver` resource for tracking version number
* Run some tests to ensure the Docker image is fully functionnal
* Use a different [rolling update method with Kubernetes](https://kubernetes.io/docs/tutorials/kubernetes-basics/update-intro/), ours is a bit hard...
* Publish a GitHub release (there is a resource for that too! ) once the deployment is finished and the new version tagged
* ...


**[Romain Guichard](https://fr.linkedin.com/in/romainguichard/en)**
