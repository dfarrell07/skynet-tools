# OCPUP

This tool creates 3 OCP4 clusters on AWS and connects them with submariner.

## Prerequisites

- [go 1.12] with [$GOPATH configured]
- [awscli]
- [Route53 public hosted zone]
- openshift-dev AWS account access or any other AWS account with near admin privileges.

## Build the tool

```bash
export GO111MODULE=on
go mod vendor
go install -mod vendor
```

The **ocpup** binary will be placed under **$GOPATH/bin/** directory.

## Configure awscli 

[Configure your AWS credentials] with awscli tool.

## Create config file

Create **ocpup.yaml** in the root on the repository. The tool will read **ocpup.yaml** file by default from the project root.
If the config is placed in other directory, pass the config file location to **ocpup** tool with **--config** flag.

```bash
ocpup create clusters --config /path/to/ocpup.yaml
``` 

Config file template:

```yaml
openshift:
  version: 4.1.7
cluster1:
  clusterName: cluster1
  vpcCidr: 10.164.0.0/16
  podCidr: 10.244.0.0/14
  svcCidr: 100.94.0.0/16
  numMasters: 3
  numWorkers: 1
  numGateways: 0
  dnsDomain: devcluster.openshift.com
  platform:
    name: aws
    region: us-east-1
cluster2:
  clusterName: cluster2
  vpcCidr: 10.165.0.0/16
  podCidr: 10.248.0.0/14
  svcCidr: 100.95.0.0/16
  numMasters: 3
  numWorkers: 1
  numGateways: 1
  dnsDomain: devcluster.openshift.com
  platform:
    name: aws
    region: us-east-2
cluster3:
  clusterName: cluster3
  vpcCidr: 10.166.0.0/16
  podCidr: 10.252.0.0/14
  svcCidr: 100.96.0.0/16
  numMasters: 3
  numWorkers: 1
  numGateways: 1
  dnsDomain: devcluster.openshift.com
  platform:
    name: aws
    region: us-west-2
helm:
  helmRepo:
    url: https://releases.rancher.com/submariner-charts/latest
    name: submariner-latest
  broker:
    namespace: submariner-k8s-broker
  engine:
    namespace: submariner
    image:
      repository: rancher/submariner
      tag: v0.0.1
  routeAgent:
    namespace: submariner
    image:
      repository: rancher/submariner-route-agent
      tag: v0.0.1
authentication:
  pullSecret: '{"auths"...}'
  sshKey: ssh-rsa xxx
```

Important config variables:

| Variable Name | Description                                                                                                               |
|:------------- |:------------------------------------------------------------------------------------------------------------------------- |
| dnsDomain     | AWS Route53 hosted zone domain name that you own. If not using openshift-dev account, please create a public hosted zone. | 
| pullSecret    | Security credentials from [Red Hat portal], please put this credentials in single quotes ''.                              | 
| sshKey        | SSH pub key from your workstation. Must have the corresponding private key.                                               |

Any region is supported as long as it has at least 3 availability zones a,b and c.

## Create clusters:

```bash
ocpup create clusters
```

The tool will create **.config** directory with the openshift install assets for each cluster.

The **.openshift-install.log** file in each cluster directory will contain a detailed log and cluster details.

The **bin** directory will contain all the required tools to interact with clusters.

After the installation is complete, the export command for kubconfig files will be printed on screen.

| Cluster Name | Type        | Cluster CIDR  | Service CIDR  | DNS Suffix                        |
|:-------------|:------------|:--------------|:--------------|:----------------------------------|
| cluster1     | AWS Broker  | 10.164.0.0/16 | 100.94.0.0/16 | cluster1.devcluster.openshift.com |
| cluster2     | AWS Gateway | 10.165.0.0/16 | 100.95.0.0/16 | cluster2.devcluster.openshift.com |
| cluster3     | AWS Gateway | 10.166.0.0/16 | 100.96.0.0/16 | cluster3.devcluster.openshift.com |

## Update submariner deployment:

Update submariner resources from config file, the image values will be read from ocpup.yaml.
```bash
ocpup update submariner
```

Update submariner resources from command line.
```bash
ocpup update submariner --engine rancher/submariner:v0.0.2 --routeagent rancher/submariner-route-agent:v0.0.2
```

Reinstall submariner with values from config file, the image values will be read from ocpup.yaml.
```bash
ocpup update submariner --reinstall
```

Reinstall submariner with image values from command line.
```bash
ocpup update submariner --engine rancher/submariner:v0.0.2 --routeagent rancher/submariner-route-agent:v0.0.2 --reinstall
```

If any of the arguments is omitted the values will be taken from ocpup.yaml config file.

## Destroy clusters:

```bash
ocpup destroy clusters
```

The deletion process takes up to 45 minutes, please be patient.

**Please remove your resources after you complete your testing.**

## VERY IMPORTANT

**UNDER NO CIRCUMSTANCES, DO NOT COMMIT ocpup.yaml FILE TO GIT!** 

<!--links-->
[go 1.12]: https://blog.golang.org/go1.12
[awscli]: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html
[Configure your AWS credentials]: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html
[Red Hat portal]: https://cloud.redhat.com/openshift/install/aws/installer-provisioned
[Route53 public hosted zone]: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/AboutHZWorkingWith.html
[$GOPATH configured]: https://github.com/golang/go/wiki/SettingGOPATH