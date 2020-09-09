---
Title: Automatic build with Github Actions and Github Container Registry
Date: 2020-09-06
Category: Github
Summary: With Github, you have one tool to store your code, build it and push it into a Docker Registry
Author: Romain Guichard
image: images/thumbnails/github-actions.png
imgSocialNetwork: images/og/github-registry-actions.png
lang: en
---

Today, September 3rd, Github Container Registry is released. It's a new Container
Registry service hosted by Github and a competitor to [Quay](https://quay.io),
[Docker Hub](https://hub.docker.com) or
[Google Cloud Registry](https://cloud.google.com/container-registry?hl=fr).
A few months ago, Github released Github
Actions to fill the gap with Gitlab-CI, this gap is closing with the
official integration of that Registry.

Github has been the corner stone for the OSS comunity for a very long time. But
lately, some competitors had disturbed the establishment. Gitlab has more and
more features, including a CI tool, a Container Registry and a deep integration
with Kubernetes. The hegemony of Github was disputed and after [Microsoft took
over](https://en.wikipedia.org/wiki/GitHub#Acquisition_by_Microsoft)
, it needs to change and evolve.

Github Actions, a few months ago, and Github Registry, now, are the response.

```
The GitHub Container Registry allows you to seamlessly host and manage Docker
container images in your organization or personal user account on GitHub.
GitHub Container Registry allows you to configure who can manage and access
packages using fine-grained permissions.
```

We will briefly present this new Container Registry then we will leverage all
Github tools to make a perfect integration chain from a simple application code to a
stored Docker image.

# Let's start manually

First of all, you need to generate a Personal Access Token to access the
Github Registry. This token must have the following rights :

- read:packages
- write:packages
- delete:packages

![pat](/images/github-registry/pat.png)

You can then login using the token as your password :

```
$ docker login ghcr.io --username rguichard
Password:
WARNING! Your password will be stored unencrypted in /home/rguichard/.docker/config.json.
Configure a credential helper to remove this warning. See
https://docs.docker.com/engine/reference/commandline/login/#credentials-store

Login Succeeded
```

We can test it :

```
$ docker tag particule/helloworld:latest ghcr.io/rguichard/helloworld:latest
$ docker push ghcr.io/rguichard/helloworld:latest
The push refers to repository [ghcr.io/rguichard/helloworld]
f0ca7466070b: Pushed
4d0213a4a2a2: Pushed
b0ffedf1c11d: Pushed
c69d0bc6c5e1: Pushed
af14cc7c88b4: Pushed
07fb6d95fd24: Pushed
57b2d92ab0bb: Pushed
8539d1fe4fab: Pushed
latest: digest: sha256:1d29a51c76a7ba2db6fad2266094b5a2e1989e54e7618e20fd33a13817ee9572 size: 1986
```

It works !

![image-uploaded](/images/github-registry/image-uploaded.png)


# Github Actions and Github Registry

[Github Actions](https://github.com/features/actions) is a way to automate all
your software workflows with a CI/CD
integrated with Github. Build, test, and deploy your code right from GitHub.

As always, we are going to use a simple application, the same we used many
times before, a single web page application.

<https://github.com/particuleio/helloworld>

### Github secrets

Our pipeline will need the permission to push our Docker image into Github
Registry. We need to pass on our Personal Access Token.

![secret repo](/images/github-registry/gh-secret.png)

### A simple pipeline

```
$ cat .github/workflows/prod.yml
cat prod.yml
name: 'build'

on:
  push:
    branches:
    - master
  pull_request:

jobs:
  build:
    name: 'Build'
    runs-on: ubuntu-latest
    steps:
      - name: "Build:checkout"
        uses: actions/checkout@v2
      - name: 'Build:dockerimage'
        uses: docker/build-push-action@v1
        with:
          registry: ghcr.io
          username: "rguichard"
          password: ${{ secrets.PAT }}
          repository: rguichard/helloworld
          tags: latest
```

Don't forget to set the correct `registry`, otherwise you will try to
authenticate to the official Docker registry.

![](/images/github-registry/github-actions-sucess.png)

### Conclusion

A Container Registry is a simple tool. You just build, tag and push. Docker Hub
has been the undisputed leader for some time now. [Quay](https://quay.io) and
[Google Cloud Registry](https://cloud.google.com/container-registry?hl=fr) are
more and more used, especially by the cloud native ecosystem. It's always good
when a new participant comes into play. Will you migrate your Docker images
from Docker Hub to Github Registry ?


[Romain Guichard](https://www.linkedin.com/in/romainguichard/), CEO &
Co-founder
