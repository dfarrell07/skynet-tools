# Create Kubernetes cluster on AWS EKS for prow deployment

## Prerequisites

- [Terraform](https://learn.hashicorp.com/terraform/getting-started/install.html). Please note that this module uses
  terraform [0.12](https://www.terraform.io/upgrade-guides/0-12.html).
- Create [AWS Instance Key Pair](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html#having-ec2-create-your-key-pair),
  copy the key to your ~/.ssh folder and modify the key name. Please not that the key name is AWS key
  name and not local file name.

```hcl
locals {
  key_name = "key-name"
}
```

- Get your ***external/public*** IP [here](https://www.whatismyip.com/) and modify the ***allowed_ips*** list.
  Each single ip must end with ***/32*** mask. This list can contain multiple addresses with correct subnet mask.

```hcl
locals {
  allowed_ips = ["1.2.3.4/32"]
}
```

- [Create](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html#Using_CreateAccessKey)
  and [configure](https://docs.aws.amazon.com/sdk-for-java/v1/developer-guide/setup-credentials.html) AWS credentials.

## Optional

Create aws S3 [private bucket](https://docs.aws.amazon.com/quickstarts/latest/s3backup/step-1-create-bucket.html).
The bucket will be used to store the terraform state. If you prefer not to create a bucket,
please remove the following section from ***main.tf***.

```hcl
terraform {
  backend "s3" {
    bucket = "bucket-name"
    key    = "folder/terraform.tfstate"
    region = "region"
  }
}
```

If you would like to use a bucket, please adjust the following values in ***main.tf*** backend settings.

| Variable    | Description                                 |
| :---------- | :------------------------------------------ |
| bucket-name | Name of the aws bucket.                     |
| folder      | Folder inside the bucket to save the state. |
| region      | AWS region to deploy the infrastructure.    |

Modify the region.

```hcl
provider "aws" {
  region = "eu-west-1"
}
```

If region was changed, please modify the [availability zones](https://gist.github.com/neilstuartcraig/0ccefcf0887f29b7f240).

```hcl
subnet_az_list = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
```

### Run the installation

Modify the following module settings in ***main.tf*** if required:

```hcl
module "eks-prow-cluster" {
  source               = "./eks-prow-cluster"
  cluster_name         = "prow-cluster1"
  eks_k8s_version      = "1.12"
  workers_desired_num  = 2
  workers_min_num      = 2
  workers_max_num      = 2
  worker_instance_type = "t3.medium"
  vpc_index            = "10.166"
}
```

| Variable             | Description                                                 |
| :------------------- | :---------------------------------------------------------- |
| cluster_name         | Name of the EKS cluster.                                    |
| eks_k8s_version      | The k8s version for EKS engine.                             |
| workers_desired_num  | The desired number of worker servers in auto scaling group. |
| workers_min_num      | The minimum number of worker servers in auto scaling group. |
| workers_max_num      | The maximum number of worker servers in auto scaling group. |
| worker_instance_type | AWS instance type for worker servers.                       |
| vpc_index            | The CIDR index for VPC that will host all workers.          |

```bash
cd skynet-tools/tools/aws-eks-prow
terraform init
terraform apply --auto-approve
```

After the module finishes to run you will have EKS cluster with alb-ingress support.

#### Prepare and apply prow configuration. [k8s test-infra documentation](https://github.com/kubernetes/test-infra/blob/master/prow/getting_started_deploy.md)

- [Create Github Bot Personal Access Token](https://help.github.com/en/articles/creating-a-personal-access-token-for-the-command-line).
  Token must have public_repo and repo:status scopes (and repo for private repos). The token must belong to the bot user.
  The bot user must be an owner of the organization. Create a variable with value of the created token.

```bash
oauth_token=xxx
```

- Generate a secret for github hooks.

```bash
hmac_token=$(openssl rand -hex 32)
```

- Get access to EKS server. The ***cluster_name*** variable is from ***main.tf***.

```bash
aws eks update-kubeconfig --name ${cluster_name} --kubeconfig ~/.kube/${cluster_name}-config
export KUBECONFIG=$HOME/.kube/${cluster_name}-config
```

- Create the secrets for default namespace.

```bash
kubectl create secret generic hmac-token --from-literal=hmac=$hmac_token
kubectl create secret generic ssh-secret --from-literal=ssh-secret=1234
kubectl create secret generic oauth-token --from-literal=oauth=$oauth_token
```

- Create configMaps.

```bash
kubectl create configmap config --from-file=eks-prow-cluster/config/config.yaml
kubectl create configmap plugins --from-file=eks-prow-cluster/config/plugins.yaml
kubectl create configmap label-config --from-file=eks-prow-cluster/config/labels.yaml
```

- [Create GCS bucket and gcs-credentials](https://github.com/kubernetes/test-infra/blob/master/prow/getting_started_deploy.md#configure-cloud-storage).
  After [downloading](https://cloud.google.com/sdk/gcloud/) the gcloud tool and authenticating,
  the following script will execute the above steps for you. Change the bucket name.

```bash
gcloud iam service-accounts create prow-gcs-publisher # step 1
identifier="$(gcloud iam service-accounts list --filter 'name:prow-gcs-publisher' --format 'value(email)')"
gsutil mb gs://${change_me_bucket_name}/ # step 2
gsutil iam ch allUsers:objectViewer gs://${change_me_bucket_name} # step 3
gsutil iam ch "serviceAccount:${identifier}:objectAdmin" gs://${change_me_bucket_name} # step 4
gcloud iam service-accounts keys create --iam-account "${identifier}" service-account.json # step 5
kubectl create secret generic gcs-credentials --from-file=service-account.json # step 6
```

- Label one of the nodes for ghproxy

```bash
kubectl get nodes -o wide | awk 'FNR > 1 {print $1}'
kubectl label node ${one_of_the_nodes_internal_dns} dedicated=ghproxy
```

- Modify the ***plugins.yaml*** and ***config.yaml*** in the eks-prow-cluster/config folder to match your github org,repo and gcs bucket created.
- Create prow resources after changes.

```bash
kubectl apply -f eks-prow-cluster/config/prow-starter-eks.yaml
```

- Create the secrets for test-pods namespace. The ***cluster_name*** variable is from ***main.tf***.

```bash
kubectl create secret generic ssh-secret --from-literal=ssh-secret=1234 -n test-pods
kubectl create secret generic gcs-credentials --from-file=service-account.json -n test-pods
```

- Run cron jobs to sync labels and apply branch protection.

```bash
kubectl create job --from=cronjob/label-sync label-sync-one-time
kubectl create job --from=cronjob/branchprotector branchprotector-one-time
```

- Get the ingress external alb DNS name. Wait for DNS record to be populated.

```bash
kubectl get ing prow-ing | awk ' FNR == 2 {print $3}'
```

- Create CNAME or ALIAS dns record to point to alb ingress dns.
- Modify the plank settings in ***config.yaml*** in the eks-prow-cluster/config folder to match your dns name.
- Apply changes.

```bash
cd eks-prow-cluster/config/
make
```

- [Create github hook in your repository](https://github.com/kubernetes/test-infra/blob/master/prow/getting_started_deploy.md#add-the-webhook-to-github).
  The hook should use the DNS record created and hmac secret created. The hook can be created on org or repo level.
- Setup metrics server

```bash
$(mktemp -d)
git clone https://github.com/kubernetes-incubator/metrics-server.git
cd metrics-server
kubectl apply -f deploy/1.8+/
```

### Remove the cloud resources.

```bash
# From eks-prow-cluster folder.
kubectl delete -f eks-prow-cluster/config/prow-starter-eks.yaml
terraform destroy --auto-approve
rm service-account.json
```
