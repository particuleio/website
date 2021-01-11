---
Title: Gérer votre boite à outils Cloud Native avec asdf
Date: 2020-06-01
Category: Random
Summary: Gérer vos versions d'application par projets avec asdf, à chaque client sa version de kubectl et sa version de Terraform !
Author: Kevin Lefevre
image: images/thumbnails/kubernetes.png
imgSocialNetwork: images/og/asdf.png
lang: fr
---

Aujourd'hui, nous vous proposons un article un petit peu diffèrent puisque nous
n'allons parler ni de Cloud provider, ni de Kubernetes, ni de GitOps, enfin si
mais nous allons nous concentrer sur notre machine locale.

Pour être honnête nous allons quand même parler de technologies Cloud Native, mais
surtout d'outils clients. Prenons un exemple avec `kubectl`, la CLI de
Kubernetes : suivant les versions de Kubernetes déployées, `kubectl` [supporte une
ou deux versions de décalage mais pas plus](https://kubernetes.io/docs/setup/release/version-skew-policy/).
Si vous managez plusieurs clusters, avec des versions différentes, gérer `kubectl` localement
devient vite impossible et vous vous retrouvez rapidement à `curl -LO
https://storage.googleapis.com/kubernetes-release/release/$VOTRE_VERSION/bin/linux/amd64/kubectl`
un peu n'importe où. Nous l'avons tous fait. C'est un problème aussi vieux que
les paquets des systèmes et les langages de programmation (Hello `pip` et
`virtualenv`, `rvm`, etc.).

Aujourd'hui étant donné le nombre d'outils Cloud Native distribués en Go avec
des releases tous les 4 jours, cela devient également un enfer pour les DevOps
de gérer leur toolbox, par exemple pour ne citer que ces outils :

* Les versions de `Terraform`
* Les versions de `Terragrunt`
* Les versions de `Helm`
* Les versions de `minikube`
* `inserer le votre ici`

C'est ici qu'intervient [`asdf`](https://asdf-vm.com/#/).

ASDF permet de gérer simplement des versions de composants de deux façons :

* de manière global
* de manière locale

ASDF supporte de [multiples
plugins](https://github.com/asdf-vm/asdf-plugins/tree/master/plugins) et peut
être facilement étendu avec des plugins personnalisés.

### Installation

```console
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.7.8
```

Puis ajoutez dans votre shell `rc` et rechargez votre session :

```console
. $HOME/.asdf/asdf.sh
```

`asdf` est ensuite disponible dans votre shell :

```console
version: v0.7.8-4a3e3d6

MANAGE PLUGINS
  asdf plugin add <name> [<git-url>]       Add a plugin from the plugin repo OR, add a Git repo
                                           as a plugin by specifying the name and repo url
  asdf plugin list [--urls] [--refs]       List installed plugins. Optionally show git urls and git-ref.
  asdf plugin list all                     List plugins registered on asdf-plugins repository with URLs
  asdf plugin remove <name>                Remove plugin and package versions
  asdf plugin update <name> [<git-ref>]    Update a plugin to latest commit or a particular git-ref.
  asdf plugin update --all                 Update all plugins


MANAGE PACKAGES
  asdf install [<name> <version>]          Install a specific version of a package or,
                                           with no arguments, install all the package
                                           versions listed in the .tool-versions file
  asdf uninstall <name> <version>          Remove a specific version of a package
  asdf current                             Display current version set or being used for all packages
  asdf current <name>                      Display current version set or being used for package
  asdf where <name> [<version>]            Display install path for an installed or current version
  asdf which <command>                     Display the path to an executable
  asdf shell <name> <version>              Set the package version in the current shell
  asdf local <name> <version>              Set the package local version
  asdf global <name> <version>             Set the package global version
  asdf list <name>                         List installed versions of a package
  asdf list all <name>                     List all versions of a package


UTILS
  asdf exec <command> [args..]             Executes the command shim for current version
  asdf env <command> [util]                Runs util (default: `env`) inside the environment used for command shim execution.
  asdf reshim <name> <version>             Recreate shims for version of a package
  asdf shim-versions <command>             List on which plugins and versions is command available
  asdf update                              Update asdf to the latest stable release
  asdf update --head                       Update asdf to the latest on the master branch

"Late but latest"
-- Rajinikanth
```

### Gestion des plugins

Pour utiliser `asdf` il faut ensuite rajouter les plugins souhaités. Pour notre
exemple nous allons rajouter :

* `terraform`
* `helm`
* `kubectl`

```console
asdf plugin add terraform
asdf plugin add helm
asdf plugin add kubectl
```

### Installation de composants globaux

Une fois les plugins installés nous pouvons installer des versions spécifiques
ou les `latest` puis ensuite set les versions utilisées globalement :

```console
asdf install terraform 0.12.26
asdf install kubectl 1.18.0
asdf install helm 3.2.1

asdf global terraform 0.12.26
asdf global kubectl 1.18.0
asdf global helm 3.2.1
```

La commande `asdf global` vous permet de définir les versions utilisées par
défaut. Techniquement ces informations sont stockées dans `~/.tool-versions`.

```
cat ~/.tool-versions

kind 0.7.0
kubectl 1.18.0
minikube 1.7.2
terraform-docs v0.8.2
stern 1.11.0
terragrunt 0.23.23
terraform 0.12.26
helm 3.2.0
kubeseal 0.9.7
gohugo 0.69.2
aws-iam-authenticator 0.5.0
pulumi 2.2.1
```

### Gestion de versions locales

Nous arrivons maintenant à la partie qui nous intéresse, la gestion des
versions par projets. En plus de la commande `asdf global` il existe la commande
`asdf local` qui permet de générer un fichier `.tool-versions` dans un
répertoire arbitraire. Il est également possible de générer le fichier
`.tool-versions` directement.

Prenons un exemple de différents projets / clients avec la structure de fichiers
suivante :

```
    .
├── clientA
│   ├── .tool-versions
│   └── test
└── clientB
    ├── .tool-versions
    ├── test

```

Les sous dossiers sont purement fictifs et sont la pour montrer la récursivité du
fichier `.tool-versions`.

Par exemple dans le fichier `.tool-versions` du `clientA` :

```console
terraform 0.11.14
helm 2.2.3
kubectl 1.6.0
```

Et `clientB` :

```console
terraform 0.12.26
helm 3.2.0
kubectl 1.16.8
```

`ASDF` supporte l'installation de paquets depuis le fichier `.tool-versions` si
ceux ci ne sont pas présents. Par exemple dans le dossier `clientA` :

```console
asdf install

Downloading helm from https://get.helm.sh/helm-v2.2.3-linux-amd64.tar.gz to /tmp/helm_XXoDcv/helm-v2.2.3-linux-amd64.tar.gz
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 11.8M  100 11.8M    0     0  3402k      0  0:00:03  0:00:03 --:--:-- 3402k
Creating bin directory
Cleaning previous binaries
Copying binary
Downloading kubectl from https://storage.googleapis.com/kubernetes-release/release/v1.6.0/bin/linux/amd64/kubectl
Downloading terraform version 0.11.14 from https://releases.hashicorp.com/terraform/0.11.14/terraform_0.11.14_linux_amd64.zip
Cleaning terraform previous binaries
Creating terraform bin directory
Extracting terraform archive
```

Ensuite depuis n'importe quel dossier du dossier `clientA`, vérifier les versions
de logiciels :

```console
terraform -version
Terraform v0.11.14

helm version --client
Client: &version.Version{SemVer:"v2.2.3", GitCommit:"1402a4d6ec9fb349e17b912e32fe259ca21181e3", GitTreeState:"clean"}

kubectl version --client
Client Version: version.Info{Major:"1", Minor:"6", GitVersion:"v1.6.0", GitCommit:"fff5156092b56e6bd60fff75aad4dc9de6b6ef37", GitTreeState:"clean", BuildDate:"2017-03-28T16:36:33Z", GoVersion:"go1.7.5", Compiler:"gc", Platform:"linux/amd64"}
```

### Conclusion

Ce petit outil nous est vite devenu indispensable pour gérer les
environnements
des nos différents clients chez Particule. Une liste assez [conséquente de
plugins est déjà supportés](https://github.com/asdf-vm/asdf-plugins).

Même sans gérer les versions localement, cela reste un outil très utile pour
gérer vos versions de logiciels globales indépendamment des paquets du système
d'exploitation.

Pour aller plus loin, je vous invite à vous [référer à la documentation
officielle](https://asdf-vm.com/#/core-manage-asdf-vm).

[**Kevin Lefevre**](https://www.linkedin.com/in/kevinlefevre/)
