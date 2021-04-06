---
Title: "CI/CD using Github Actions, AWS ECR and ECS Fargate"
Date: 2021-04-05
Category: Amazon Web Services
Summary: Using AWS Github Actions, push to a private ECR and deploy ECS tasks on Fargate
Author: Theo "Bob" Massard
image: images/thumbnails/ecs-fargate.png
imgSocialNetwork: images/og/cicd-ecr-ecs.png
lang: en
---

AWS Fargate is a CaaS (Container as a Service) solution allowing to deploy
containers on [Amazon ECS][fargate-ecs] and [Amazon EKS][fargate-eks] without provisionning
EC2 instances. The goal is to only reserve the resources required for a container,
thus reducing the maintenance cost and the engineering needed to deploy applications.

AWS provides [Github Actions][aws-gh-actions] to allow integrating
Continuous Integration and Continuous Delivery to AWS solutions.

In this article, we will setup the main components of a serverless infrastructure
on AWS using [Terraform][terraform], a set of jobs on [Github Actions][gh-actions]
and an example application to try out this configuration.

_note: we talked about building container images [in the past][cicd-github-registry],
this article focuses on AWS integrations !_

[cicd-github-registry]: https://particule.io/en/blog/cicd-github-registry/
[aws-gh-actions]: https://github.com/aws-actions/
[gh-actions]: https://github.com/features/actions
[terraform]: https://www.terraform.io/
[fargate-eks]: https://docs.aws.amazon.com/eks/latest/userguide/fargate.html
[fargate-ecs]: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html

## Creating an ECS infrastructure on AWS

In order to deploy ECS tasks, we have the following requirements to expose our
containers:

- An Application Load Balancer which will serve as a public entrypoint
- An ECS Cluster to deploy our service
- An ECS Service to run our ECS Tasks
- An Elastic Container Registry (ECR) to store our container images

We will setup the AWS infrastructure using the [AWS Terraform Provider][tf-aws-provider].

We won't cover the VPC configuration and will rely on an existing VPC, referenced
by its id in `local.vpc["id"]`.

```hcl
data "aws_vpc" "main" {
  id = local.vpc["id"]  # vpc-xx1x1x1x
}

data "aws_subnet" "subnets" {
  # availability_zones = ["eu-west-3a", "eu-west-3b", "eu-west-3c"]
  for_each          = toset(local.vpc.availability_zones)
  vpc_id            = data.aws_vpc.main.id
  availability_zone = each.value
}
```

Using the VPC-related datasources, we gathered the subnets which will be used
for our [Application Load Balancer][aws-alb].

For the sake of this example, we'll use the ALB as our web entrypoint,
switching its `internal` attribute to `false` to expose it.

```hcl
resource "aws_lb" "alb" {
  name               = local.lb["name"]     # tf-alb
  internal           = local.lb["internal"] # false
  load_balancer_type = "application"

  subnets            = [for s in data.aws_subnet.subnets : s.id]
}
```

In addition, we'll define a _Load Balancer Target Group_ as well as
a _Load Balancer Listener_ to route traffic to our target group.

```hcl
resource "aws_lb_target_group" "group" {
  name        = local.lb.target_group["name"]
  port        = local.lb.target_group["port"]
  protocol    = local.lb.target_group["protocol"]
  vpc_id      = data.aws_vpc.main.id
  target_type = "ip"

  depends_on = [aws_lb.alb]
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.group.arn
  }
}
```

We can now setup our Application Load Balancer using Terraform:

```console
$ terraform apply -auto-approve
...
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:

app_url = "tf-alb-1725491528.eu-west-3.elb.amazonaws.com"
$ curl -I tf-alb-1725491528.eu-west-3.elb.amazonaws.com
HTTP/1.1 503 Service Temporarily Unavailable
Server: awselb/2.0
```

Our ALB is fully functioning ! It is now time to create some ECS tasks.
We will start by creating the cluster, defining a ECS Service and a basic task
to try out the configuration.

In order to leverage the capabilities of Fargate, we simply have
to define `FARGATE` as the only capacity provider for our cluster.

```hcl
resource "aws_ecs_cluster" "cluster" {
  name               = local.ecs["cluster_name"]  # "ecs-cluster"
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = "100"
  }
}
```

Using this ECS Cluster, we can now define our task and the corresponding
ECS service. In order to run tasks on ECS, we need to provide an
execution role (see [Task execution IAM role][ecs-execution-role] for more details).

[ecs-execution-role]: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html

_We will not cover the IAM permissions in this article but the complete repository
is available in [this repository][gh-repository]._

```hcl
resource "aws_ecs_task_definition" "task" {
  family = "service"
  requires_compatibilities = [
    "FARGATE",
  ]
  execution_role_arn = aws_iam_role.fargate.arn
  network_mode       = "awsvpc"
  cpu                = 256
  memory             = 512
  container_definitions = jsonencode([
    {
      name      = local.container.name   # "application"
      image     = local.container.image  # "particule/helloworld"
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "service" {
  name            = local.ecs.service_name
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.task.arn
  desired_count   = 1

  network_configuration {
    subnets          = [for s in data.aws_subnet.subnets : s.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.group.arn  # our target group
    container_name   = local.container.name           # "application"
    container_port   = 80
  }
  capacity_provider_strategy {
    base              = 0
    capacity_provider = "FARGATE"
    weight            = 100
  }
}
```

In the configuration above, we create an ECS Task Definition with 1/4th of a CPU
and 512MB of RAM, the smallest possible specifications. We also specify the container
we want to run, we'll start with a default "Hello World" application using
`particule/helloworld`.

The list of resource specifications is available in the [ECS - Fargate][ecs-fargate-resources]
documentation.

[ecs-fargate-resources]: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html

```console
$ terraform apply -auto-approve
...
Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:

app_url = "tf-alb-1725491528.eu-west-3.elb.amazonaws.com"
$ curl -I tf-alb-1725491528.eu-west-3.elb.amazonaws.com
HTTP/1.1 200 OK
Server: nginx/1.10.1
X-Powered-By: PHP/5.6.30
```

We now have the infrastructure to deploy ECS task ! We can now finalize
our terraform configuration by creating an ECR to publish our images to, as
well as some credentials to implement the CI/CD in Github Actions.

```hcl
resource "aws_ecr_repository" "repository" {
  name                 = local.ecr["repository_name"]  # "repository"
  image_tag_mutability = "MUTABLE"
}
```

We can now create an IAM user which will be used for our CI.

```hcl
resource "aws_iam_user" "publisher" {
  name = "ecr-publisher"
  path = "/serviceaccounts/"
}

resource "aws_iam_access_key" "publisher" {
  user = aws_iam_user.publisher.name
}
```

In order to ease the configuration of our Github repository secrets, we
define some Terraform outputs:

```hcl
output "publisher_access_key" {
  value       = aws_iam_access_key.publisher.id
  description = "AWS_ACCESS_KEY to publish to ECR"
}

output "publisher_secret_key" {
  value       = aws_iam_access_key.publisher.secret
  description = "AWS_SECRET_ACCESS_KEY to upload to the ECR"
  sensitive   = true
}

output "ecr_url" {
  value       = aws_ecr_repository.repository.repository_url
  description = "The ECR repository URL"
}
```

Let's apply this last bit of configuration to finalize our setup !

```console
$ terraform apply -auto-approve
...
Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:

app_url = "tf-alb-1725491528.eu-west-3.elb.amazonaws.com"
aws_region = "eu-west-3"
container_name = "application"
ecr_repository_name = "app-registry"
ecr_url = "111111111111.dkr.ecr.eu-west-3.amazonaws.com/app-registry"
ecs_cluster = "ecs-cluster"
ecs_service = "ecs-service"
publisher_access_key = "AAAAAAAAAAAAAAAAAAAA"
publisher_secret_key = <sensitive>
```

[tf-aws-provider]: https://registry.terraform.io/providers/hashicorp/aws/latest
[aws-alb]: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/introduction.html

Our AWS infrastructure is now complete ! We can follow-up with the
configuration of our Github repository.

## Configuring our repository's CI/CD

As stated earlier, AWS maintains [some github actions][aws-gh-actions] which
can be used to automate deployements and to interact with AWS services.

We will configure a [Workflow][gh-workflow] with some mock integration tests
and a deployment that will build a Docker image, publish it to our ECR and
update the corresponding ECS task.

[gh-workflow]: https://docs.github.com/en/actions/reference/workflow-syntax-for-github-actions

_note: interactions with github will be made using the [Github CLI][gh-cli] (`gh`)._

[gh-cli]: https://github.com/cli/cli

Let's start by creating the base workflow file and defining the mock integration
job. We want our Workflow to run on every commit related to the `main` branch,
and to deploy it every time a new tag is pushed (and the CI passes !).

```yaml
---
name: "workflow"

'on':
  push:
    branches:
      - main
    tags:
      - "*"
  pull_request:
    branches:
      - main

jobs:
  integration:
    name: "CI"
    runs-on: "ubuntu-latest"
    steps:
      - name: "Checkout Code"
        uses: "actions/checkout@v2"

      - name: "Lint code"
        run: echo "Linting repository"

      - name: "Run unit tests"
        run: echo "Running unit tests"
```

As previously mentioned, the integration job's sole purpose is to create a dependency
to experiment with the deployment, which we will define below.

![workflow](/images/github-actions/cicd-workflow.png)

We want the CD to be executed:

- if the ingration tests (unit tests, linting) are passing
- if the trigger event is a tag

```yaml
  cd:
    name: "Deployment"
    runs-on: "ubuntu-latest"
    needs:
      - ci
    if: startsWith(github.ref, 'refs/tags/')
```

Using AWS github actions, we will execute the following tasks:

- configure the AWS credentials ([configure-aws-credentials][gh-aws-credentials])
- log in to our previously created ECR ([amazon-ecr-login][gh-aws-ecr-login])
- build and push our Docker image
- edit the ECS task with the new image ([ecr-render-task][gh-aws-ecs-render])
- update the ECS service ([ecr-deploy-task][gh-aws-ecs-deploy])

[gh-aws-credentials]: https://github.com/aws-actions/configure-aws-credentials
[gh-aws-ecr-login]: https://github.com/aws-actions/amazon-ecr-login
[gh-aws-ecs-render]: https://github.com/aws-actions/amazon-ecs-render-task-definition
[gh-aws-ecs-deploy]: https://github.com/aws-actions/amazon-ecs-deploy-task-definition

The Deployment job steps are defined below:

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v1
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: ${{ secrets.AWS_REGION }}

- name: Login to Amazon ECR
  id: login-ecr
  uses: aws-actions/amazon-ecr-login@v1

- name: Build, tag, and push image to Amazon ECR
  id: build-image
  env:
    ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
    ECR_REPOSITORY: ${{ secrets.ECR_REPOSITORY }}
    IMAGE_TAG: ${{ steps.vars.outputs.tag }}
  run: |
    docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
    docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
    echo "::set-output name=image::$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG"

- name: Download task definition
  run: |
    aws ecs describe-task-definition --task-definition service \
    --query taskDefinition > task-definition.json

- name: Fill in the new image ID in the Amazon ECS task definition
  id: task-def
  uses: aws-actions/amazon-ecs-render-task-definition@v1
  with:
    task-definition: task-definition.json
    container-name: application
    image: ${{ steps.build-image.outputs.image }}

- name: Deploy Amazon ECS task definition
  uses: aws-actions/amazon-ecs-deploy-task-definition@v1
  with:
    task-definition: ${{ steps.task-def.outputs.task-definition }}
    service: ${{ secrets.ECS_SERVICE }}
    cluster: ${{ secrets.ECS_CLUSTER }}
    wait-for-service-stability: true
```

We now have to configure our Github Repository secrets ! Using the outputs we
defined in Terraform, we can easily set them using `gh`.

```console
$ gh secret set AWS_ACCESS_KEY_ID -b $(terraform output -raw publisher_access_key)
✓ Set secret AWS_ACCESS_KEY_ID for tbobm/tf-ecr-ecs-gh-deploy
$ gh secret set AWS_SECRET_ACCESS_KEY -b $(terraform output -raw publisher_secret_key)
✓ Set secret AWS_SECRET_ACCESS_KEY for tbobm/tf-ecr-ecs-gh-deploy
$ gh secret set AWS_REGION -b $(terraform output -raw aws_region)
✓ Set secret AWS_REGION for tbobm/tf-ecr-ecs-gh-deploy
$ gh secret set ECR_REPOSITORY_NAME -b $(terraform output -raw ecr_repository_name)
✓ Set secret ECR_REPOSITORY_NAME for tbobm/tf-ecr-ecs-gh-deploy
$ gh secret set ECS_CLUSTER -b $(terraform output -raw ecs_cluster)
✓ Set secret ECS_CLUSTER for tbobm/tf-ecr-ecs-gh-deploy
$ gh secret set ECS_SERVICE -b $(terraform output -raw ecs_service)
✓ Set secret ECS_SERVICE for tbobm/tf-ecr-ecs-gh-deploy
$ gh secret list
AWS_ACCESS_KEY_ID      Updated 2021-03-30
AWS_REGION             Updated 2021-03-30
AWS_SECRET_ACCESS_KEY  Updated 2021-03-30
ECS_CLUSTER            Updated 2021-03-30
ECR_REPOSITORY_NAME    Updated 2021-03-30
ECS_SERVICE            Updated 2021-03-30
```

So far we have:

- [x] Setup our AWS infrastructure
- [x] Created a Github Actions Workflow
- [x] Configured our repository secrets

Let's try out our configuration with a basic API.

## Testing our workflow

Currently, our ECS task is running an Hello World application. We'll commit and
push an example HTTP API to validate our deployment workflow.

```console
$ ls
app.py  Dockerfile  README.md  requirements.txt  terraform
$ curl tf-alb-1725491528.eu-west-3.elb.amazonaws.com
<html>
<head>
  <!-- ... -->
</head>
<body>
  <img id="logo" src="logo.png" />
  <h1>Hello world!</h1>
  <h3>My hostname is ip-172-31-1-133.eu-west-3.compute.internal</h3>
</body>
$ git add app.py Dockerfile requirements.txt
$ git commit -m 'add example application'
$ git tag 0.0.0
$ git push origin --tags
Total 0 (delta 0), reused 0 (delta 0), pack-reused 0
To github.com:tbobm/tf-ecr-ecs-gh-deploy.git
 * [new tag]         0.0.0 -> 0.0.0
```

This will trigger the complete workflow, starting with the Integration job
and proceeding with the Deployment job afterwards, if the CI is successful.

![ecr-ecr-workflow](/images/github-actions/ecr-ecs-workflow.png)

After a couple of minutes, we can try to access our ALB's public
address to ensure the ECS task got properly updated:

```console
curl tf-alb-1725491528.eu-west-3.elb.amazonaws.com
{
  "message": "Hello from ip-172-31-13-81.eu-west-3.compute.internal"
}
```

Our new application successfully got deployed ! We can see that the
IP changed as AWS created a new instance of our task behind the scene.

## Final note

This configuration is not aimed for production purpose _as is_ but
can be a great way to perform unit tests and integration tests on an
application !

Some key points that could be implemented to extend this setup:

- Extend the task definition to implement a more realist application
(environment variables, volumes, access to other services)
- Logging using AWS CloudWatch ([documentation][ecs-cloudwatch])
- Autoscaling for your ECS Service ([documentation][ecs-scaling])
- Configure Route53 as the public entrypoint ([documentation][aws-route53])

The complete repository is available at [tbobm/tf-ecr-ecs-gh-deploy][gh-repository].

[gh-repository]: https://github.com/tbobm/tf-ecr-ecs-gh-deploy/
[ecs-cloudwatch]: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/using_cloudwatch_logs.html
[ecs-scaling]: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-auto-scaling.html
[aws-route53]: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-to-elb-load-balancer.html

[**Theo "Bob" Massard**](https://www.linkedin.com/in/tbobm/), Cloud Native Engineer
