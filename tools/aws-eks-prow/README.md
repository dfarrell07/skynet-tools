# Create Kubernetes cluster on AWS EKS for prow deployment

## Prerequisites

- [Terraform](https://learn.hashicorp.com/terraform/getting-started/install.html). Please note that this module uses
  terraform [0.12](https://www.terraform.io/upgrade-guides/0-12.html).
- Create [AWS Key](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html#having-ec2-create-your-key-pair),
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
The bucket will be used to store the terraform state. If you would like not create a bucket,
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
  allowed_ips          = "${local.allowed_ips}"
  key_name             = "${local.key_name}"
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

After the module finishes to run you will EKS cluster with alb-ingress support.

#### Prepare and apply prow configuration. [k8s test-infra documentation](https://github.com/kubernetes/test-infra/blob/master/prow/getting_started_deploy.md)

- [Create Secrets](https://github.com/kubernetes/test-infra/blob/master/prow/getting_started_deploy.md#create-the-github-secrets)
- [Create GCS bucket](https://github.com/kubernetes/test-infra/blob/master/prow/getting_started_deploy.md#configure-cloud-storage)
- Modify the ***plugins.yaml*** and ***config.yaml*** in the eks-prow-cluster/config folder to match your github org,repo and gcs bucket created.
- Create plugins and config configMaps:

```bash
kubectl create configmap config --from-file=eks-prow-cluster/config/config.yaml
kubectl create configmap plugins --from-file=eks-prow-cluster/config/plugins.yaml
```

- Create label config:

```bash
kubectl create configmap label-config --from-file=eks-prow-cluster/config/labels.yaml
```

- Create prow resources:

```bash
kubectl apply -f eks-prow-cluster/config/prow-starter.yaml
```

- [Create github hook in your repository](https://github.com/kubernetes/test-infra/blob/master/prow/getting_started_deploy.md#add-the-webhook-to-github)

### Remove the cloud resources.

```bash
cd skynet-tools/tools/aws-eks-prow
kubectl delete -f prow-starter.yaml
terraform destroy --auto-approve
```
