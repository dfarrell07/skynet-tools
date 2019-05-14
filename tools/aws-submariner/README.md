# Create 3 kubernetes cluster on AWS and deploy rancher submariner.

### Prerequisites

1. [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)

2. [Terraform](https://learn.hashicorp.com/terraform/getting-started/install.html)

3. Create [AWS Key](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html) and modify:
```hcl-terraform
locals {
  key_name = "key-name"
}
```

4.[Create](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html#Using_CreateAccessKey) and [configure](https://docs.aws.amazon.com/sdk-for-java/v1/developer-guide/setup-credentials.html) AWS credentials.


#### Optional
Create aws S3 [private bucket](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html).
The bucket will be used to store the terraform state. If you would like not create a bucket, please remove the following from ***main.tf***.

```hcl-terraform
terraform {
  backend "s3" {
    bucket = "bucket-name"
    key    = "folder/terraform.tfstate"
    region = "region"
  }
}
```

If you would like to use a bucket, please adjust the following values in ***main.tf***.

|Variable|Description |
:--- |:--- |
bucket-name | Name of the aws bucket. |
folder | Folder inside the bucket to save the state. |
region | AWS region to deploy the infrastructure. |

Modify the region.
```hcl-terraform
provider "aws" {
  region = "eu-west-1"
}
```

Modify the [availability zones](https://docs.aws.amazon.com/AmazonS3/latest/gsg/CreatingABucket.html).
```hcl-terraform
  subnet_az_list = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
```

### Run the installation

```bash
cd skynet-tools/tools/aws-submariner
terraform init
terraform apply --auto-approve
```

### Remove the cloud resources.
```bash
terraform destroy --auto-approve
```


