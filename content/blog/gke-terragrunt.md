---
Category: Kubernetes
lang: en
Date: 2018-04-09
Title: Manage multiple Kubernetes clusters on GKE with Terragrunt
Summary: Terragrunt is a thin wrapper around Terraform to keep your infrastructure DRY, let's see how this can be applied to GKE clusters and multiple environments
Author: Kevin Lefevre
image: images/thumbnails/kubernetes.png
---

[Terragrunt](https://github.com/gruntwork-io/terragrunt) is a thin wrapper around [Terraform](https://terraform.io) to easily manage multiple environments without repeating yourself (DRY) and prevent code duplication. Let's see how we can use it to manage multiple [GKE clusters](https://cloud.google.com/kubernetes-engine/), for example, a production one and another for preproduction.

<center><img src="/images/gke-terragrunt/terraform.png" alt="terraform" width="300" align="middle"></center>

![terraform](//images/gke-terragrunt/terraform.png){ width: 200px; }

# Sources

Terraform modules and configuration files used in this article can be found [here](https://github.com/Osones/cloud-infra/tree/master/gcp/terraform)

# Requirements

- Working [Google Cloud SDK](https://cloud.google.com/sdk/).
- `application default credentials` that Terraform can use out of the box without specifying provider configuration. To generate [`application default credentials`](https://cloud.google.com/docs/authentication/production):
```
 gcloud auth application-default login
```
This generates a default access key for your apps, using you account rights. This will allow terraform to run out of the box with the same right as your GCP account.
- [Terraform](https://www.terraform.io/downloads.html)
- [Terragrunt](https://github.com/gruntwork-io/terragrunt/releases) : standalone Go binary, can be install anywhere is path if not available in distribution packages.
- At least two GCP projects:
```
gcloud projects create gke-blog-prod
Create in progress for [https://cloudresourcemanager.googleapis.com/v1/projects/gke-blog-prod].
Waiting for [operations/pc.4802334422007730518] to finish...done.


gcloud projects create gke-blog-prod
Create in progress for [https://cloudresourcemanager.googleapis.com/v1/projects/gke-blog-preprod].
Waiting for [operations/pc.3759965873816129841] to finish...done.
```
- Billing enabled on both projects: `https://console.developers.google.com/project/${PROJECT_ID}/settings`
- Google Container API enabled on both projects:
```
gcloud services enable container.googleapis.com --project gke-blog-preprod
Waiting for async operation operations/tmo-acf.ff5396f9-57ab-422c-b7eb-f9bf9cf060a7 to complete...
Operation finished successfully. The following command can describe the Operation details:
gcloud services operations describe operations/tmo-acf.ff5396f9-57ab-422c-b7eb-f9bf9cf060a7


gcloud services enable container.googleapis.com --project gke-blog-prod
Waiting for async operation operations/tmo-acf.81d7dd57-1df2-44ac-8225-ccc46d98f1e4 to complete...
Operation finished successfully. The following command can describe the Operation details:
gcloud services operations describe operations/tmo-acf.81d7dd57-1df2-44ac-8225-ccc46d98f1e4
```

# Terragrunt

Terragrunt enables separation of Terraform modules and configuration files (variables) without [code duplication](https://github.com/gruntwork-io/terragrunt#keep-your-terraform-code-dry). It is mainly developed by [Gruntwork](https://www.gruntwork.io/).

<center><img src="/images/gke-terragrunt/gruntwork.png" alt="gruntwork" width="300" align="middle"></center>

Like Terraform, you can also reuse remote modules. Our GKE modules are stored [on Github](https://github.com/Osones/cloud-infra/tree/master/gcp/terraform).

The directory structure is:

```
.
└── terraform
    └── modules
        └── gke
            ├── main.tf
            └── variables.tf
```

Modules are reusable and fully customizable, no hard coded values are present.

The specific configuration is done in another directory, for example `env`:

```
└── env
    ├── prod
    │   ├── terraform.tfvars
    │   └── gke
    │       └── terraform.tfvars
    └── preprod
        ├── terraform.tfvars
        └── gke
            └── terraform.tfvars
```

Each directory contains specific variables relative to each environment and inside each modules variables specific to each modules. The root `terraform.tfvars` contains variables common to all modules of a specific environment.

# Customize each environment

Terraform modules and configuration files used in this article can be found [here](https://github.com/Osones/cloud-infra/tree/master/gcp/terraform)

## GKE variables

Let's create a new repository with the same structure as before. The [required variables](https://github.com/Osones/cloud-infra/blob/master/gcp/terraform/modules/gke/variables.tf) to setup a GKE cluster are defined in the module.

[`env/preprod/gke/terraform.tfvars`](https://github.com/Osones/cloud-infra/blob/master/gcp/terraform/example_env/preprod/gke/terraform.tfvars) for the preproduction environment:

```
terragrunt = {
  include {
    path = "${find_in_parent_folders()}"
  }

  terraform {
    source = "git::ssh://git@github.com/osones/cloud-infra.git//gcp/terraform/modules/gke"
  }
}

project = "gke-blog-preprod"
cluster_name = "gke-blog-preprod"
node_count = 1
max_node_count = 3
min_node_count = 1
node_count = 1
admin_username = "admin"
admin_password = "200791-76f9-4c70-afd7-5b7b7be1c46e"
machine_type = "n1-standard-1"
disk_size_gb = "100"
master_zone = "europe-west1-b"
additional_zones = [
  "europe-west1-c",
  "europe-west1-d"
  ]
min_master_version = "1.9.6-gke.0"
initial_default_pool_name = "unused-default-pool"
default_pool_name = "default-pool"
daily_maintenance_window_start_time = "00:00"
env = "preprod"
```

We only need to define the variables and we will use the remote module stored on Github.

Then let's do the same for prod environment.

[`env/prod/gke/terraform.tfvars`](https://github.com/Osones/cloud-infra/blob/master/gcp/terraform/example_env/prod/gke/terraform.tfvars) for the prod environment:

```
terragrunt = {
  include {
    path = "${find_in_parent_folders()}"
  }

  terraform {
    source = "git::ssh://git@github.com/osones/cloud-infra.git//gcp/terraform/modules/gke"
  }
}

project = "gke-blog-prod"
cluster_name = "gke-blog-prod"
node_count = 1
max_node_count = 3
min_node_count = 1
node_count = 1
admin_username = "admin"
admin_password = "200791-76f9-4c70-afd7-5b7b7be1c46e"
machine_type = "n1-standard-1"
disk_size_gb = "100"
master_zone = "europe-west1-b"
additional_zones = [
  "europe-west1-c",
  "europe-west1-d"
  ]
min_master_version = "1.9.6-gke.0"
initial_default_pool_name = "unused-default-pool"
default_pool_name = "default-pool"
daily_maintenance_window_start_time = "00:00"
env = "prod"
```

## Manage remote state

Terragrunt also support remote state and the official [Terraform backend](https://www.terraform.io/docs/backends/types/gcs.html). We can also avoid code duplication and specify the backend only once.

[Google Cloud Storage](https://cloud.google.com/storage/) is supported by Terraform and also support remote state locking (prevent users from running Terraform simultaneously).

Each environment state will be store in its own GCS bucket. Terragrunt supports creating bucket automatically with S3, but not with GCS so let's create one bucket per environment:

```
gsutil mb -p gke-blog-preprod gs://gke-blog-preprod-tf-remote-state
Creating gs://gke-blog-preprod-tf-remote-state/...

gsutil mb -p gke-blog-prod gs://gke-blog-prod-tf-remote-state
Creating gs://gke-blog-prod-tf-remote-state/...
```

Then a `terraform.tfvars` in the root folder of each environment will tell Terraform to store the remote state in this bucket, this root file is reused by all the modules inside the environment. This is defined [here](https://github.com/Osones/cloud-infra/blob/master/gcp/terraform/example_env/preprod/gke/terraform.tfvars#L3) for example with:

```
  include {
    path = "${find_in_parent_folders()}"
  }
```

[`env/preprod/terraform.tfvars`](https://github.com/Osones/cloud-infra/blob/master/gcp/terraform/example_env/preprod/terraform.tfvars) content:

```
terragrunt = {
  remote_state {
    backend = "gcs"
    config {
      bucket         = "gke-blog-preprod-remote-state"
      prefix         = "${path_relative_to_include()}"
      region         = "europe-west1"
      project        = "gke-blog-preprod"
    }
  }
}
```

[`env/prod/terraform.tfvars`](https://github.com/Osones/cloud-infra/blob/master/gcp/terraform/example_env/prod/terraform.tfvars) content:

```
terragrunt = {
  remote_state {
    backend = "gcs"
    config {
      bucket         = "gke-blog-prod-remote-state"
      prefix         = "${path_relative_to_include()}"
      region         = "europe-west1"
      project        = "gke-blog-prod"
    }
  }
}
```

Our final directory structure should look like this:

```
.
├── preprod
│   ├── gke
│   │   └── terraform.tfvars
│   └── terraform.tfvars
└── prod
    ├── gke
    │   └── terraform.tfvars
    └── terraform.tfvars
```

Finally we can just run `terragrunt apply-all`.

You should end up with on cluster in each projects, and each Terraform state stored in a GCS bucket.

<center><img src="/images/gke-terragrunt/gke-terragrunt-1.png" alt="GKE-1" width="1200" align="middle"></center>

<center><img src="/images/gke-terragrunt/gke-terragrunt-2.png" alt="GKE-2" width="1200" align="middle"></center>

```
gcloud container clusters list --project gke-blog-prod
NAME           LOCATION        MASTER_VERSION  MASTER_IP       MACHINE_TYPE   NODE_VERSION  NUM_NODES  STATUS
gke-blog-prod  europe-west1-b  1.9.6-gke.0     35.189.251.203  n1-standard-1  1.9.6-gke.0   3          RUNNING

gcloud container clusters list --project gke-blog-preprod
NAME              LOCATION        MASTER_VERSION  MASTER_IP      MACHINE_TYPE   NODE_VERSION  NUM_NODES  STATUS
gke-blog-preprod  europe-west1-b  1.9.6-gke.0     35.195.157.89  n1-standard-1  1.9.6-gke.0   3          RUNNING
```

```
gsutil ls -p gke-blog-preprod gs://gke-blog-preprod-tf-remote-state/gke
gs://gke-blog-preprod-tf-remote-state/gke/default.tfstate

gsutil ls -p gke-blog-prod gs://gke-blog-prod-tf-remote-state/gke
gs://gke-blog-prod-tf-remote-state/gke/default.tfstate
```
Terraform modules and configuration files used in this article can be found [here](https://github.com/Osones/cloud-infra/tree/master/gcp/terraform)

# Conclusion

Terragrunt allows you to reuse generic modules for multiple environments, here we only use the GKE module, but you can add multiple modules inside the `env` folder, for example if you need a MySQL database or other GCP services, these modules will also use the GCP bucket for remote state locking and storage and all your environment state will be stored remotely.
