# Create 3 kubernetes cluster on AWS and deploy rancher submariner.

## Prerequisites

- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
- [Terraform](https://learn.hashicorp.com/terraform/getting-started/install.html)
- Create [AWS Key](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html), copy the key to your ~/.ssh
  folder and modify the key name. You can also use the **libra** key provided for openshift-dev account.
  Copy **libra.pem** key to your ~/.ssh folder.

```hcl
locals {
  aws_key_name   = "libra"
  local_key_name = "libra.pem"
}
```

- Get your ***external/public*** IP [here](https://www.whatismyip.com/) and modify the ***allowed_ips*** list.
  Each single ip must end with ***/32*** mask. This list can contain multiple addresses with correct subnet mask.

```hcl
locals {
  allowed_ips = ["1.2.3.4/32"]
}
```

- Adjust the **redhat_id** to you Kerberos id.

```hcl
locals {
  redhat_id = "dgroisma"
}
```

- [Create](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html#Using_CreateAccessKey)
  and [configure](https://docs.aws.amazon.com/sdk-for-java/v1/developer-guide/setup-credentials.html) AWS credentials.

## Optional

Create aws S3 [private bucket](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html).
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

If you would like to use a bucket, please adjust the following values in ***main.tf***.

| Variable    | Description                                 |
| :---------- | :------------------------------------------ |
| bucket-name | Name of the aws bucket.                     |
| folder      | Folder inside the bucket to save the state. |
| region      | AWS region to deploy the infrastructure.    |

Modify the region.

```hcl
provider "aws" {
  region = "us-east-1"
}
```

If region was changed, please modify the [availability zones](https://gist.github.com/neilstuartcraig/0ccefcf0887f29b7f240).

```hcl
locals {
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
}
```

### Run the installation

```bash
cd skynet-tools/tools/aws-submariner
terraform init
terraform apply --auto-approve
```

You can pass the AWS credentials on runtime. Configuring AWS credentials is not required.

```bash
cd skynet-tools/tools/aws-submariner
AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=xxx terraform init
AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=xxx terraform apply --auto-approve
```

### Use exported kube configs.

The kube configs for the clusters can will reside inside **ansible/tmp/** folder. Export the configs:

```bash
export KUBECONFIG=$(echo $(git rev-parse --show-toplevel)/tools/aws-submariner/ansible/tmp/cluster{1..3}-conf | sed 's/ /:/g')
```

### Remove the cloud resources.

```bash
cd skynet-tools/tools/aws-submariner
terraform destroy --auto-approve
```

You can pass the AWS credentials on runtime. Configuring AWS credentials is not required.

```bash
cd skynet-tools/tools/aws-submariner
AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=xxx terraform destroy --auto-approve
```

**NOTE**: **PLEASE DO NOT FORGET TO DELETE YOUR RESOURCES AFTER YOU FINISHED!**