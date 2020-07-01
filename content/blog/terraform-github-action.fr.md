---
Title: Automatiser le déploiement de clusters Kubernetes EKS avec Github Action
Date: 2020-06-29
Category: Kubernetes
Summary: Comment utiliser Github Action pour déployer du code Terraform/Terragrunt ?
Author: Kevin Lefevre
image: images/thumbnails/github-actions.png
imgSocialNetwork: images/og/terraform-githubaction.png
lang: fr
---

Nous avons pour habitude de déployer des clusters Kubernetes avec EKS via
Terraform et notamment via le [module
officiel](https://github.com/terraform-aws-modules/terraform-aws-eks) que nous
automatisons [via Terragrunt](https://github.com/clusterfrak-dynamics/teks).

Nous allons voir aujourd'hui comment connecter cette partie Terraform/Terragrunt
à [Github Action](https://github.com/features/actions), l'outil de CI/CD de
Github.

Le dépôt de code [tEKS](https://github.com/clusterfrak-dynamics/teks) présente
un squelette que vous pouvez réutiliser en tant que [template
Github](https://help.github.com/en/github/creating-cloning-and-archiving-repositories/creating-a-template-repository) :

![github_template](/images/github-actions/github-template.png)

La structure de fichier est la suivante :

```console
.
├── CODEOWNERS
├── LICENSE
├── README.md
├── mkdocs.yml
├── requirements.txt
└── terraform
    └── live
        └── demo
            ├── common_tags.yaml
            ├── common_values.yaml
            ├── eu-west-3
            │   ├── ecr
            │   ├── eks
            │   ├── eks-addons
            │   ├── eks-namespaces
            │   └── vpc
            └── terragrunt.hcl
```

Chaque dossier dans `eu-west-3` représente un module Terraform donné, nous
allons préparer la pipeline suivante pour chaque dossier dans `live` :

1. Installation des prérequis
2. Déploiement des modules par ordres de dépendance
3. Vérification du bon déploiement des pods
4. Destruction des modules dans l'ordre inverse de dépendance.

### Déclaration des secrets Github

Dans un premier temps nous avons besoin de déclarer des secrets pour accéder à
AWS, pour cela dans la console Github dans les paramètres du repository ou de
l'organisation :

![secret_repo](/images/github-actions/secret-repo.png)

Il faut déclarer les variables d'environnement AWS suivantes :

* `AWS_ACCESS_KEY_ID`
* `AWS_SECRET_ACCESS_KEY`

### Déclaration de la pipeline éphémère `demo`

Dans le dossier `demo`, si vous souhaitez tester en live sur un compte AWS, il
faudra adapter les valeurs présentes dans `common_values.yaml` afin de
représenter votre configuration :

```yaml
---
aws_account_id: 161285725140
aws_region: eu-west-3
prefix: cfd-particule
default_domain_name: clusterfrak-dynamics.io
```

Si vous possédez une zone [AWS route53](https://aws.amazon.com/route53/), la
remplir ici vous permettra d'accéder au monitoring du cluster out *of the box*.

Dans le dépôt, dans `.github/workflows` le fichier `demo.yml` défini la
pipeline pour le dossier `terraform/live/demo/*`. Tous les changements dans ce
dossier déclencherons cette pipeline :

```yaml
name: 'terragrunt:env:demo'

on:
  push:
    branches:
    - master
    paths:
    - 'terraform/live/demo/**'
  pull_request:
```

Ensuite nous allons installer les prérequis, cette partie installe les
différents outils nécessaire tels que Terraform, Helm, Terragrunt, etc ainsi que
de préparer les variables d'environnement AWS :

```yaml
jobs:
  terraform:
    name: 'terragrunt:env:demo'
    runs-on: ubuntu-latest
    steps:
    - name: checkout
      uses: actions/checkout@v2

    - name: 'asdf:install'
      uses: asdf-vm/actions/install@v1.0.0

    - name: 'terraform:provider:kubectl'
      run: |
        mkdir -p ~/.terraform.d/plugins
        curl -Ls https://api.github.com/repos/gavinbunney/terraform-provider-kubectl/releases/latest | jq -r ".assets[] | select(.browser_download_url | contains(\"$(uname -s | tr A-Z a-z)\")) | select(.browser_download_url | contains(\"amd64\")) | .browser_download_url" | xargs -n 1 curl -Lo ~/.terraform.d/plugins/terraform-provider-kubectl
        chmod +x ~/.terraform.d/plugins/terraform-provider-kubectl

    - name: 'terraform:setup'
      uses: hashicorp/setup-terraform@v1
      with:
        terraform_wrapper: false

    - name: 'aws:credentials'
      uses: aws-actions/configure-aws-credentials@v1
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: eu-west-1
```

Puis, pour chaque module nous allons `terraform init`, `terraform fmt`  et
`terraform validate` puis `terraform apply` :

```yaml
 - name: 'terragrunt:init:vpc'
      run: terragrunt init --terragrunt-non-interactive
      working-directory: terraform/live/demo/eu-west-3/vpc

    - name: 'terragrunt:fmt:vpc'
      run: terragrunt fmt -check
      working-directory: terraform/live/demo/eu-west-3/vpc

    - name: 'terragrunt:validate:vpc'
      run: terragrunt validate
      working-directory: terraform/live/demo/eu-west-3/vpc

    - name: 'terragrunt:plan:vpc'
      run: terragrunt plan --terragrunt-non-interactive
      working-directory: terraform/live/demo/eu-west-3/vpc

    - name: 'terragrunt:apply:vpc'
      run: terragrunt apply -auto-approve
      working-directory: terraform/live/demo/eu-west-3/vpc

    - name: 'terragrunt:init:eks'
      run: terragrunt init --terragrunt-non-interactive
      working-directory: terraform/live/demo/eu-west-3/eks

    - name: 'terragrunt:fmt:eks'
      run: terragrunt fmt -check
      working-directory: terraform/live/demo/eu-west-3/eks

    - name: 'terragrunt:validate:eks'
      run: terragrunt validate
      working-directory: terraform/live/demo/eu-west-3/eks

    - name: 'terragrunt:plan:eks'
      run: terragrunt plan --terragrunt-non-interactive
      working-directory: terraform/live/demo/eu-west-3/eks

    - name: 'terragrunt:apply:eks'
      run: terragrunt apply -auto-approve
      working-directory: terraform/live/demo/eu-west-3/eks

    - name: 'terragrunt:apply:eks:upload-kubeconfig'
      uses: actions/upload-artifact@v1
      with:
        name: kubeconfig
        path: kubeconfig
      working-directory: terraform/live/demo/eu-west-3/eks

    - name: 'terragrunt:init:eks-addons'
      run: terragrunt init --terragrunt-non-interactive
      working-directory: terraform/live/demo/eu-west-3/eks-addons

    - name: 'terragrunt:fmt:eks-addons'
      run: terragrunt fmt -check
      working-directory: terraform/live/demo/eu-west-3/eks-addons

    - name: 'terragrunt:validate:eks-addons'
      run: terragrunt validate
      working-directory: terraform/live/demo/eu-west-3/eks-addons

    - name: 'terragrunt:plan:eks-addons'
      run: terragrunt plan --terragrunt-non-interactive
      working-directory: terraform/live/demo/eu-west-3/eks-addons

    - name: 'terragrunt:apply:eks-addons'
      run: terragrunt apply -auto-approve
      working-directory: terraform/live/demo/eu-west-3/eks-addons
```

Nous allons attendre que tous les pods soient `Ready` :

```yaml
    - name: 'kubectl:wait-for-pods'
      run: kubectl --kubeconfig=kubeconfig wait --for=condition=Ready pods --all --all-namespaces --timeout 300s
      working-directory: terraform/live/demo/eu-west-3/eks
```

Et finalement détruire l'infrastructure dans l'ordre inverse de dépendance :

```yaml
    - name: 'terragrunt:destroy:eks-addons'
      run: terragrunt destroy -auto-approve
      working-directory: terraform/live/demo/eu-west-3/eks-addons
      continue-on-error: true
      if: "!contains(github.event.head_commit.message, 'ci keep')"

    - name: 'terragrunt:destroy:eks-addons:cleanup-stale-state'
      run: terragrunt state list 2>/dev/null | xargs terragrunt state rm
      working-directory: terraform/live/demo/eu-west-3/eks-addons
      continue-on-error: true
      if: "!contains(github.event.head_commit.message, 'ci keep')"

    - name: 'terragrunt:destroy:eks'
      run: terragrunt destroy -auto-approve
      working-directory: terraform/live/demo/eu-west-3/eks
      continue-on-error: true
      if: "!contains(github.event.head_commit.message, 'ci keep')"

    - name: 'terragrunt:destroy:vpc'
      run: terragrunt destroy -auto-approve
      working-directory: terraform/live/demo/eu-west-3/vpc
      continue-on-error: true
      if: "!contains(github.event.head_commit.message, 'ci keep')"
```

Ici, la partie `if: "!contains(github.event.head_commit.message, 'ci keep')"`
permet de garder l'infra et de ne pas la détruire dans le cas où le message de
commit contient la chaine de caractère `ci keep`.

Une fois le code push, la pipeline s'exécute dans la console Github :

![demo_deploy](/images/github-actions/demo-deploy.png)

Cette pipeline n'est pas parfaite, c'est un premier jet qui peut être amélioré
au fur et à mesure des évolutions de Github Action :

* Pour le moment pas d'approval manuel comme c'est le cas sur Gitlab
* Impossible d'empêcher l'exécution en parallèle de deux pipelines (2 Pull
    request en même temps bloqueront le state terraform)
* Pas de possibilité de force trigger une pipeline ([sauf avec des hack](https://github.community/t/github-actions-manual-trigger-approvals/16233/32)

Pour le moment, cette pipeline est faite pour tester une infrastructure
éphémère.

Pour aller plus loin, déployons un nouvel environnement, pour cela, dupliquons
l'environnement de `demo` en `prod`.

### Création de l'environnement permanent de production

```bash
cp -ar demo/prod
```

Il faut ensuite changer les valeurs de `common_tags` et `common_values` :

```yaml
---
Owner: clusterfrak-dynamics
Env: prod
Terraform: "0.12"
```

```yaml
---
aws_account_id: 161285725140
aws_region: eu-west-3
prefix: cfd-particule-prod
default_domain_name: clusterfrak-dynamics.io
```

Reprenons la même pipeline en enlevant la partie destruction et en remplaçant
`demo` par `prod` dans `.github/workflows/prod.yml` et supprimons le build sur
les `pull-requests` :

```yaml
name: 'terragrunt:env:prod'

on:
  push:
    branches:
    - master
    paths:
    - 'terraform/live/prod/**'

jobs:
  terraform:
    name: 'terragrunt:env:prod'
    runs-on: ubuntu-latest
    steps:
    - name: checkout
      uses: actions/checkout@v2

    - name: 'asdf:install'
      uses: asdf-vm/actions/install@v1.0.0

    - name: 'terraform:provider:kubectl'
      run: |
        mkdir -p ~/.terraform.d/plugins
        curl -Ls https://api.github.com/repos/gavinbunney/terraform-provider-kubectl/releases/latest | jq -r ".assets[] | select(.browser_download_url | contains(\"$(uname -s | tr A-Z a-z)\")) | select(.browser_download_url | contains(\"amd64\")) | .browser_download_url" | xargs -n 1 curl -Lo ~/.terraform.d/plugins/terraform-provider-kubectl
        chmod +x ~/.terraform.d/plugins/terraform-provider-kubectl

    - name: 'terraform:setup'
      uses: hashicorp/setup-terraform@v1
      with:
        terraform_wrapper: false

    - name: 'aws:credentials'
      uses: aws-actions/configure-aws-credentials@v1
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: eu-west-1

    - name: 'terragrunt:init:vpc'
      run: terragrunt init --terragrunt-non-interactive
      working-directory: terraform/live/prod/eu-west-3/vpc

    - name: 'terragrunt:fmt:vpc'
      run: terragrunt fmt -check
      working-directory: terraform/live/prod/eu-west-3/vpc

    - name: 'terragrunt:validate:vpc'
      run: terragrunt validate
      working-directory: terraform/live/prod/eu-west-3/vpc

    - name: 'terragrunt:plan:vpc'
      run: terragrunt plan --terragrunt-non-interactive
      working-directory: terraform/live/prod/eu-west-3/vpc

    - name: 'terragrunt:apply:vpc'
      run: terragrunt apply -auto-approve
      working-directory: terraform/live/prod/eu-west-3/vpc

    - name: 'terragrunt:init:eks'
      run: terragrunt init --terragrunt-non-interactive
      working-directory: terraform/live/prod/eu-west-3/eks

    - name: 'terragrunt:fmt:eks'
      run: terragrunt fmt -check
      working-directory: terraform/live/prod/eu-west-3/eks

    - name: 'terragrunt:validate:eks'
      run: terragrunt validate
      working-directory: terraform/live/prod/eu-west-3/eks

    - name: 'terragrunt:plan:eks'
      run: terragrunt plan --terragrunt-non-interactive
      working-directory: terraform/live/prod/eu-west-3/eks

    - name: 'terragrunt:apply:eks'
      run: terragrunt apply -auto-approve
      working-directory: terraform/live/prod/eu-west-3/eks

    - name: 'terragrunt:init:eks-addons'
      run: terragrunt init --terragrunt-non-interactive
      working-directory: terraform/live/prod/eu-west-3/eks-addons

    - name: 'terragrunt:fmt:eks-addons'
      run: terragrunt fmt -check
      working-directory: terraform/live/prod/eu-west-3/eks-addons

    - name: 'terragrunt:validate:eks-addons'
      run: terragrunt validate
      working-directory: terraform/live/prod/eu-west-3/eks-addons

    - name: 'terragrunt:plan:eks-addons'
      run: terragrunt plan --terragrunt-non-interactive
      working-directory: terraform/live/prod/eu-west-3/eks-addons

    - name: 'terragrunt:apply:eks-addons'
      run: terragrunt apply -auto-approve
      working-directory: terraform/live/prod/eu-west-3/eks-addons

    - name: 'kubectl:wait-for-pods'
      run: kubectl --kubeconfig=kubeconfig wait --for=condition=Ready pods --all --all-namespaces --timeout 300s
      working-directory: terraform/live/prod/eu-west-3/eks
```

Une fois tous le code pushé, le workflow de prod démarre :

![prod_workflow](/images/github-actions/prod-workflow.png)

Une fois le run terminé, le fichier
[kubeconfig](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)
est récupérable dans la partie `Artifacts` :

![kubeconfig_artifact](/images/github-actions/kubeconfig-artifact.png)

Avec le compte AWS correspondant correctement configurer sur votre machine :

```console
$ kubectl --kubeconfig=/home/klefevre/Downloads/kubeconfig get nodes
NAME                                       STATUS   ROLES    AGE   VERSION
ip-10-0-1-126.eu-west-3.compute.internal   Ready    <none>   19m   v1.16.8-eks-e16311
ip-10-0-2-150.eu-west-3.compute.internal   Ready    <none>   19m   v1.16.8-eks-e16311
ip-10-0-3-224.eu-west-3.compute.internal   Ready    <none>   19m   v1.16.8-eks-e16311
```

Si vous aviez déjà une zone route53 configurée sur votre compte et que vous
l'avez renseignée dans `common_values.yaml`, vous pouvez accéder directement à
[Grafana](https://grafana.com/) :

```console
$ kubectl --kubeconfig=/home/klefevre/Downloads/kubeconfig -n monitoring get ingress

NAME                          HOSTS                                 ADDRESS                                                                  PORTS     AGE
karma                         karma.clusterfrak-dynamics.io   ad8315d46de3c416694732864d785dfc-463529602.eu-west-3.elb.amazonaws.com   80, 443   16m
prometheus-operator-grafana   grafana.clusterfrak-dynamics.io       ad8315d46de3c416694732864d785dfc-463529602.eu-west-3.elb.amazonaws.com   80, 443   17m

$ kubectl --kubeconfig=/home/klefevre/Downloads/kubeconfig -n monitoring get secrets/prometheus-operator-grafana -o json | jq -r '.data."admin-password"' | base64 -d
gTj5cmPwqBh0Ojye%
```

Vous pouvez vous authentifier sur `grafana.$VOTRE_DOMAINE` (sans `%` a la fin du
mot de passe) :

![grafana](/images/github-actions/grafana.png)

### Conclusion

Cette méthode, que ce soit via Github action ou un autre outil de CI/CD permet
de tendre vers le principe [GitOps](https://www.weave.works/technologies/gitops/) pour l'infrastructure, bien sur elle n'est pas
parfaite et nous la feront évoluer au fur et à mesure de nos et cela dépend bien
évidemment des différents use case que vous pourriez avoir.

Elle constitue néanmoins une bonne base sur laquelle construire votre
infrastructure as code et commencer à déporter l'exécution de celle ci vers un
environnement mieux maitrisé que les laptops des DevOps.

Github action est aujourd'hui gratuit pour les dépôts publics.

N'hésitez pas à [jouer avec notre
template](https://github.com/clusterfrak-dynamics/teks) et à remplir des issues
et pull request si besoin :)

A bientôt,

[Kevin Lefevre](https://www.linkedin.com/in/kevinlefevre/), CTO &
Co-founder
