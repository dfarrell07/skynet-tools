# Create 3 kubernetes cluster on AWS and deploy rancher submariner.

## Prerequisites

- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
- [Terraform](https://learn.hashicorp.com/terraform/getting-started/install.html)
- Create [AWS Key](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html), copy the key to your ~/.ssh
  folder and modify the key name. Please not that the key name is AWS key name and not local file name.

```hcl
locals {
  key_name = "key-name"
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
  region = "eu-west-1"
}
```

If region was changed, please modify the [availability zones](https://gist.github.com/neilstuartcraig/0ccefcf0887f29b7f240).

```hcl
subnet_az_list = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
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
