package cmd

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/awserr"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/ec2"
	"github.com/dustin/go-humanize"
	"github.com/mholt/archiver"
	secv1 "github.com/openshift/api/security/v1"
	scc "github.com/openshift/client-go/security/clientset/versioned/typed/security/v1"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
	"gopkg.in/yaml.v2"
	"io"
	"io/ioutil"
	corev1 "k8s.io/api/core/v1"
	extensionsv1beta1 "k8s.io/api/extensions/v1beta1"
	rbacv1 "k8s.io/api/rbac/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
	"math/rand"
	"net/http"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"text/template"
	"time"
)

type KubeConfig struct {
	APIVersion string `yaml:"apiVersion"`
	Clusters   []struct {
		Cluster struct {
			CertificateAuthorityData string `yaml:"certificate-authority-data"`
			Server                   string `yaml:"server"`
		} `yaml:"cluster"`
		Name string `yaml:"name"`
	} `yaml:"clusters"`
	Contexts []struct {
		Context struct {
			Cluster string `yaml:"cluster"`
			User    string `yaml:"user"`
		} `yaml:"context"`
		Name string `yaml:"name"`
	} `yaml:"contexts"`
	CurrentContext string `yaml:"current-context"`
	Kind           string `yaml:"kind"`
	Preferences    struct {
	} `yaml:"preferences"`
	Users []struct {
		Name string `yaml:"name"`
		User struct {
			ClientCertificateData string `yaml:"client-certificate-data"`
			ClientKeyData         string `yaml:"client-key-data"`
		} `yaml:"user"`
	} `yaml:"users"`
}

type ClusterData struct {
	ClusterName string `yaml:"clusterName"`
	Platform    string `yaml:"platform"`
	Region      string `yaml:"region"`
	VpcCidr     string `yaml:"vpcCidr"`
	PodCidr     string `yaml:"podCidr"`
	SvcCidr     string `yaml:"svcCidr"`
	NumMasters  int    `yaml:"numMasters"`
	NumWorkers  int    `yaml:"numWorkers"`
	NumGateways int    `yaml:"numGateways"`
	DNSDomain   string `yaml:"dnsDomain"`
}

type HelmData struct {
	HelmRepo struct {
		URL  string `yaml:"url"`
		Name string `yaml:"name"`
	} `yaml:"helmRepo"`
	Broker struct {
		Namespace string `yaml:"namespace"`
	} `yaml:"broker"`
	Engine struct {
		Namespace string `yaml:"namespace"`
		Image     struct {
			Repository string `yaml:"repository"`
			Tag        string `yaml:"tag"`
		} `yaml:"image"`
	} `yaml:"engine"`
	RouteAgent struct {
		Namespace string `yaml:"namespace"`
		Image     struct {
			Repository string `yaml:"repository"`
			Tag        string `yaml:"tag"`
		} `yaml:"image"`
	} `yaml:"routeAgent"`
}

type AuthData struct {
	PullSecret string `yaml:"pullSecret"`
	SSHKey     string `yaml:"sshKey"`
}

type OpenshiftData struct {
	Version string `yaml:"version"`
}

type WriteCounter struct {
	Total    uint64
	FileName string
}

func (wc *WriteCounter) Write(p []byte) (int, error) {
	n := len(p)
	wc.Total += uint64(n)
	wc.PrintProgress()
	return n, nil
}

func (wc WriteCounter) PrintProgress() {
	// Clear the line by using a character return to go back to the start and remove
	// the remaining characters by filling it with spaces
	fmt.Printf("\r%s", strings.Repeat(" ", 35))

	// Return again and print current status of download
	// We use the humanize package to print the bytes in a meaningful way (e.g. 10 MB)
	fmt.Printf("\rDownloading %s... %s complete", wc.FileName, humanize.Bytes(wc.Total))
}

func diff(lhsSlice, rhsSlice []string) (lhsOnly []string, rhsOnly []string) {
	return singleDiff(lhsSlice, rhsSlice), singleDiff(rhsSlice, lhsSlice)
}

func singleDiff(lhsSlice, rhsSlice []string) (lhsOnly []string) {
	for _, lhs := range lhsSlice {
		found := false
		for _, rhs := range rhsSlice {
			if lhs == rhs {
				found = true
				break
			}
		}

		if !found {
			lhsOnly = append(lhsOnly, lhs)
		}
	}

	return lhsOnly
}

//Download tools
func DownloadFile(url string, filepath string, filename string) error {

	// Create the file, but give it a tmp file extension, this means we won't overwrite a
	// file until it's downloaded, but we'll remove the tmp extension once downloaded.
	out, err := os.Create(filepath + ".tmp")
	if err != nil {
		return err
	}
	defer out.Close()

	// Get the data
	resp, err := http.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	// Create our progress reporter and pass it to be used alongside our writer
	counter := &WriteCounter{FileName: filename}
	_, err = io.Copy(out, io.TeeReader(resp.Body, counter))
	if err != nil {
		return err
	}

	// The progress use the same line so print a new line once it's finished downloading
	fmt.Print("\n")

	err = os.Rename(filepath+".tmp", filepath)
	if err != nil {
		return err
	}

	return nil
}

//Run terraform init
func TerraformInit() {
	log.Info("Running Terraform init.")
	cmd := exec.Command("./bin/terraform", "init")
	buf := &bytes.Buffer{}
	cmd.Stdout = buf
	cmd.Stderr = buf

	err := cmd.Start()
	if err != nil {
		log.Fatalf("Error starting Cmd: %s %s", err, buf.String())
	}

	err = cmd.Wait()
	if err != nil {
		log.Fatalf("Error waiting for terraform: %s %s", err, buf.String())
	}
	log.Debug(buf.String())
}

//Generate Psk for submariner tunnels
func GeneratePsk() string {
	var letterRunes = []rune("1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
	b := make([]rune, 64)
	for i := range b {
		b[i] = letterRunes[rand.Intn(len(letterRunes))]
	}
	return string(b)
}

//Run helm init and add a submariner repository
func HelmInit(repo string) {
	cmdName := "./bin/helm"
	initArgs := []string{"init", "--client-only"}
	addArgs := []string{"repo", "add", "submariner-latest", repo}

	cmd1 := exec.Command(cmdName, initArgs...)
	cmd2 := exec.Command(cmdName, addArgs...)
	buf := &bytes.Buffer{}
	cmd1.Stdout = buf
	cmd1.Stderr = buf
	cmd2.Stdout = buf
	cmd2.Stderr = buf

	err := cmd1.Start()
	if err != nil {
		log.Fatalf("Error starting helm: %s\n%s", err, buf.String())
	}

	err = cmd1.Wait()
	if err != nil {
		log.Fatalf("Error waiting for helm: %s\n%s", err, buf.String())
	}

	err = cmd2.Start()
	if err != nil {
		log.Fatalf("Error starting helm: %s\n%s", err, buf.String())
	}

	err = cmd2.Wait()
	if err != nil {
		log.Fatalf("Error waiting for helm: %s\n%s", err, buf.String())
	}

	log.Debugf("Helm repo %s was added.", repo)
}

//Get dependencies required for multi cluster setup
func GetDependencies(v OpenshiftData) {
	if runtime.GOOS == "linux" {
		log.Debugf("Hello from linux.")
	}

	currentDir, _ := os.Getwd()
	binDir := filepath.Join(currentDir, "bin")
	tmpDir := filepath.Join(currentDir, "tmp")
	_ = os.MkdirAll(binDir, os.ModePerm)
	_ = os.MkdirAll(tmpDir, os.ModePerm)

	if _, err := os.Stat("./bin/helm"); os.IsNotExist(err) {
		err = DownloadFile("https://storage.googleapis.com/kubernetes-helm/helm-v2.14.1-linux-amd64.tar.gz", "./tmp/helm.tar.gz", "helm")
		if err != nil {
			log.Fatal(err.Error())
		}
		_ = os.Remove("./tmp/linux-amd64")
		err = archiver.Extract("./tmp/helm.tar.gz", "linux-amd64/helm", "./tmp")
		if err != nil {
			log.Fatal(err.Error())
		}

		oldLocation := "./tmp/linux-amd64/helm"
		newLocation := "./bin/helm"
		err = os.Rename(oldLocation, newLocation)
		if err != nil {
			log.Fatal(err)
		}
	} else {
		log.Debugf("Helm already exists.")
	}

	if _, err := os.Stat("./bin/terraform"); os.IsNotExist(err) {
		err = DownloadFile("https://releases.hashicorp.com/terraform/0.12.3/terraform_0.12.3_linux_amd64.zip", "./tmp/terraform.zip", "terraform")
		if err != nil {
			log.Fatalf(err.Error())
		}

		z := archiver.Zip{
			ImplicitTopLevelFolder: false,
			OverwriteExisting:      true,
			MkdirAll:               false,
		}

		err = z.Extract("./tmp/terraform.zip", "terraform", "./bin")
		if err != nil {
			log.Fatal(err.Error())
		}
	} else {
		log.Debugf("Terraform exists.")
	}

	if _, err := os.Stat("./bin/openshift-install"); os.IsNotExist(err) {
		GetOcpTools(v.Version)
	} else {
		cmdName := "./bin/openshift-install"
		cmdArgs := []string{"version"}

		cmd := exec.Command(cmdName, cmdArgs...)
		buf := &bytes.Buffer{}
		cmd.Stdout = buf
		cmd.Stderr = buf

		err := cmd.Start()
		if err != nil {
			log.Fatalf("Error starting openshift-install: %s\n%s", err, buf.String())
		}

		err = cmd.Wait()
		if err != nil {
			log.Fatalf("Error waiting for openshift-install: %s\n%s", err, buf.String())
		}

		if strings.Contains(buf.String(), v.Version) {
			log.Debugf("OCP tools with version %s already exist.", v.Version)
		} else {
			GetOcpTools(v.Version)
		}
	}
	_ = os.RemoveAll(filepath.Join(currentDir, "tmp"))
}

//Get openshift install amd client binaries
func GetOcpTools(version string) {
	url := "https://mirror.openshift.com/pub/openshift-v4/clients/ocp" + "/" + version + "/openshift-install-linux-" + version + ".tar.gz"
	err := DownloadFile(url, "./tmp/openshift-install-linux-"+version+".tar.gz", "openshift-install")
	if err != nil {
		log.Fatal(err)
	}

	_ = os.Remove("./bin/openshift-install")
	source := "./tmp/openshift-install-linux-" + version + ".tar.gz"
	err = archiver.Extract(source, "openshift-install", "./bin")
	if err != nil {
		log.Fatal(err.Error())
	}

	url = "https://mirror.openshift.com/pub/openshift-v4/clients/ocp" + "/" + version + "/openshift-client-linux-" + version + ".tar.gz"
	err = DownloadFile(url, "./tmp/openshift-client-linux-"+version+".tar.gz", "oc")
	if err != nil {
		log.Fatal(err)
	}

	_ = os.Remove("./bin/oc")
	source = "./tmp/openshift-client-linux-" + version + ".tar.gz"
	err = archiver.Extract(source, "oc", "./bin")
	if err != nil {
		log.Fatal(err.Error())
	}
}

//Install submariner broker on cluster1
func InstallSubmarinerBroker(cl ClusterData, ns string) {
	currentDir, _ := os.Getwd()
	kubeConfigFile := filepath.Join(currentDir, ".config", cl.ClusterName, "auth", "kubeconfig")
	cmdName := "./bin/helm"
	cmdArgs := []string{
		"install", "--debug", "submariner-latest/submariner-k8s-broker",
		"--name", ns,
		"--namespace", ns,
		"--kubeconfig", kubeConfigFile,
	}

	cmd := exec.Command(cmdName, cmdArgs...)
	buf := &bytes.Buffer{}
	cmd.Stdout = buf
	cmd.Stderr = buf

	err := cmd.Start()
	if err != nil {
		log.Fatalf("Error starting helm: %s %s\n%s", cl.ClusterName, err, buf.String())
	}

	err = cmd.Wait()
	if err != nil && !strings.Contains(buf.String(), "already exists") {
		log.Fatalf("Error waiting for helm: %s %s\n%s", cl.ClusterName, err, buf.String())
	}

	log.WithFields(log.Fields{
		"cluster": cl.ClusterName,
	}).Debugf("%s %s", cl.ClusterName, buf.String())
	log.Infof("Broker was installed on %s.", cl.ClusterName)
}

//Add submariner security policy to gateway node
func AddSubmarinerSecurityContext(wg *sync.WaitGroup, cl ClusterData) {
	currentDir, _ := os.Getwd()
	kubeConfigFile := filepath.Join(currentDir, ".config", cl.ClusterName, "auth", "kubeconfig")
	config, err := clientcmd.BuildConfigFromFlags("", kubeConfigFile)
	if err != nil {
		log.Fatal(err.Error())
	}

	clientset, err := scc.NewForConfig(config)
	if err != nil {
		log.Fatal(err)
	}

	sc, err := clientset.SecurityContextConstraints().Get("privileged", metav1.GetOptions{})
	if err != nil {
		log.Fatal(err)
	}

	sec := secv1.SecurityContextConstraints{}

	sc.DeepCopyInto(&sec)

	submUsers := []string{
		"system:serviceaccount:submariner:submariner-routeagent",
		"system:serviceaccount:submariner:submariner-engine",
	}

	usersToAdd, _ := diff(submUsers, sc.Users)

	sec.Users = append(sec.Users, usersToAdd...)

	_, err = clientset.SecurityContextConstraints().Update(&sec)
	if err != nil {
		log.Fatal(err)
	}

	log.Infof("Security context updated for %s.", cl.ClusterName)
	wg.Done()

}

//Label gateway nodes as submariner gateway
func LabelGatewayNodes(wg *sync.WaitGroup, cl ClusterData) {
	infraData := ExtractInfraDetails(cl)

	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(cl.Region)},
	)

	ec2svc := ec2.New(sess)

	vpcInput := &ec2.DescribeVpcsInput{
		Filters: []*ec2.Filter{
			{
				Name:   aws.String("tag:kubernetes.io/cluster/" + infraData[0]),
				Values: []*string{aws.String("owned")},
			},
		},
	}

	vpcResult, err := ec2svc.DescribeVpcs(vpcInput)
	if err != nil {
		if aerr, ok := err.(awserr.Error); ok {
			switch aerr.Code() {
			default:
				log.Fatal(aerr.Error())
			}
		} else {
			log.Fatal(err.Error())
		}
		return
	}

	ec2Input := &ec2.DescribeInstancesInput{
		Filters: []*ec2.Filter{
			{
				Name:   aws.String("vpc-id"),
				Values: []*string{aws.String(*vpcResult.Vpcs[0].VpcId)},
			},
			{
				Name:   aws.String("tag:kubernetes.io/cluster/" + infraData[0]),
				Values: []*string{aws.String("owned")},
			},
			{
				Name:   aws.String("tag:Submariner"),
				Values: []*string{aws.String("gateway")},
			},
		},
	}

	ec2Result, err := ec2svc.DescribeInstances(ec2Input)
	if err != nil {
		if aerr, ok := err.(awserr.Error); ok {
			switch aerr.Code() {
			default:
				log.Fatal(aerr.Error())
			}
		} else {
			log.Fatal(err.Error())
		}
		return
	}

	currentDir, _ := os.Getwd()
	kubeConfigFile := filepath.Join(currentDir, ".config", cl.ClusterName, "auth", "kubeconfig")
	config, err := clientcmd.BuildConfigFromFlags("", kubeConfigFile)
	if err != nil {
		panic(err.Error())
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err.Error())
	}

	for _, instance := range ec2Result.Reservations {
		node, err := clientset.CoreV1().Nodes().Get(*instance.Instances[0].PrivateDnsName, metav1.GetOptions{})
		if err != nil {
			panic(err)
		}

		node.Labels["submariner.io/gateway"] = "true"
		_, err = clientset.CoreV1().Nodes().Update(node)
		if err != nil {
			panic(err)
		}
		log.Infof("Node %s labeled %s", node.Name, cl.ClusterName)
		wg.Done()
	}
}

//Install submariner gateway
func InstallSubmarinerGateway(wg *sync.WaitGroup, cl ClusterData, broker ClusterData, h HelmData, psk string) {
	var token string
	var ca string
	currentDir, _ := os.Getwd()
	kubeConfigFile := filepath.Join(currentDir, ".config", cl.ClusterName, "auth", "kubeconfig")

	brokerInfraData := ExtractInfraDetails(broker)

	brokerSecretData, err := ExportBrokerSecretData(broker)
	if brokerSecretData == nil || err != nil {
		log.Fatalf("Unable to get broker secret data %s: ", err)
	}

	for k, v := range brokerSecretData {
		if k == "token" {
			token = string(v)
		} else if k == "ca.crt" {
			ca = base64.StdEncoding.EncodeToString([]byte(string(v)))
		}
	}

	log.Debugf("Installing gateway %s.", cl.ClusterName)
	brokerUrl := []string{"api", brokerInfraData[2], broker.DNSDomain}
	cmdName := "./bin/helm"
	setArgs := []string{
		"ipsec.psk=" + psk,
		"broker.server=" + strings.Join(brokerUrl, ".") + ":6443",
		"broker.token=" + token,
		"broker.namespace=" + h.Broker.Namespace,
		"broker.ca=" + ca,
		"submariner.clusterId=" + cl.ClusterName,
		"submariner.clusterCidr=" + cl.VpcCidr,
		"submariner.serviceCidr=" + cl.SvcCidr,
		"submariner.natEnabled=true",
		"routeAgent.image.repository=" + h.RouteAgent.Image.Repository,
		"routeAgent.image.tag=" + h.RouteAgent.Image.Tag,
		"engine.image.repository=" + h.Engine.Image.Repository,
		"engine.image.tag=" + h.Engine.Image.Tag,
	}
	cmdArgs := []string{
		"install", "--debug", h.HelmRepo.Name + "/submariner",
		"--name", "submariner",
		"--namespace", h.Engine.Namespace,
		"--kubeconfig", kubeConfigFile,
		"--set", strings.Join(setArgs, ","),
	}

	cmd := exec.Command(cmdName, cmdArgs...)
	buf := &bytes.Buffer{}
	cmd.Stdout = buf
	cmd.Stderr = buf

	err = cmd.Start()
	if err != nil {
		log.Fatalf("Error starting helm: %s %s\n%s", cl.ClusterName, err, buf.String())
	}

	err = cmd.Wait()
	if err != nil && !strings.Contains(buf.String(), "already exists") {
		log.Fatalf("Error waiting for helm: %s %s\n%s", cl.ClusterName, err, buf.String())
	}

	log.WithFields(log.Fields{
		"cluster": cl.ClusterName,
	}).Debugf("%s %s", cl.ClusterName, buf.String())
	log.Infof("Gateway was installed on %s.", cl.ClusterName)
	wg.Done()
}

//Export submariner broker ca and token
func ExportBrokerSecretData(cl ClusterData) (map[string][]byte, error) {
	currentDir, _ := os.Getwd()
	kubeConfigFile := filepath.Join(currentDir, ".config", cl.ClusterName, "auth", "kubeconfig")
	config, err := clientcmd.BuildConfigFromFlags("", kubeConfigFile)
	if err != nil {
		log.Error(err.Error())
		return nil, err
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Error(err.Error())
		return nil, err
	}

	saClient := clientset.CoreV1().Secrets("submariner-k8s-broker")

	saList, err := saClient.List(metav1.ListOptions{FieldSelector: "type=kubernetes.io/service-account-token"})
	if err == nil && len(saList.Items) > 0 {
		for _, sa := range saList.Items {
			if strings.Contains(sa.Name, "submariner-k8s-broker-client-token") {
				b := new(bytes.Buffer)
				for key, value := range sa.Annotations {
					_, _ = fmt.Fprintf(b, "%s=\"%s\"\n", key, value)
				}
				if !strings.Contains(b.String(), "openshift.io") {
					log.Debugf("Getting data for %s %s", sa.Name, cl.ClusterName)
					return sa.Data, nil
				}
			}
		}
	} else {
		log.Errorf("Could not get broker token for %s", cl.ClusterName)
	}
	return nil, nil
}

//Wait for tiller deployment to be ready
func WaitForTillerDeployment(cls []ClusterData) {
	for _, cl := range cls {
		ctx := context.Background()
		currentDir, _ := os.Getwd()
		kubeConfigFile := filepath.Join(currentDir, ".config", cl.ClusterName, "auth", "kubeconfig")
		config, err := clientcmd.BuildConfigFromFlags("", kubeConfigFile)
		if err != nil {
			panic(err.Error())
		}

		clientset, err := kubernetes.NewForConfig(config)
		if err != nil {
			panic(err.Error())
		}

		tillerTimeout := 5 * time.Minute
		log.Infof("Waiting up to %v for tiller to be created %s...", tillerTimeout, cl.ClusterName)
		tillerContext, cancel := context.WithTimeout(ctx, tillerTimeout)
		deploymentsClient := clientset.ExtensionsV1beta1().Deployments("kube-system")
		wait.Until(func() {
			deployments, err := deploymentsClient.List(metav1.ListOptions{LabelSelector: "app=helm, name=tiller"})
			if err == nil && len(deployments.Items) > 0 {
				for _, deploy := range deployments.Items {
					if deploy.Name == "tiller-deploy" && deploy.Status.ReadyReplicas == 1 {
						log.Infof("Tiller successfully deployed to %s, ready replicas: %v", cl.ClusterName, deploy.Status.ReadyReplicas)
						cancel()
					}
				}
			}
		}, 10*time.Second, tillerContext.Done())
		err = tillerContext.Err()
		if err != nil && err != context.Canceled {
			log.Fatalf("Error waiting for tiller deployment %s %s", cl.ClusterName, err)
		}
	}
}

//Wait for submariner engine deployment ro be ready
func WaitForSubmarinerDeployment(wg *sync.WaitGroup, cl ClusterData, helm HelmData) {
	ctx := context.Background()
	currentDir, _ := os.Getwd()
	kubeConfigFile := filepath.Join(currentDir, ".config", cl.ClusterName, "auth", "kubeconfig")
	config, err := clientcmd.BuildConfigFromFlags("", kubeConfigFile)
	if err != nil {
		panic(err.Error())
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err.Error())
	}

	submarinerTimeout := 5 * time.Minute
	log.Infof("Waiting up to %v for submariner engine to be created %s...", submarinerTimeout, cl.ClusterName)
	submarinerContext, cancel := context.WithTimeout(ctx, submarinerTimeout)
	deploymentsClient := clientset.ExtensionsV1beta1().Deployments(helm.Engine.Namespace)
	wait.Until(func() {
		deployments, err := deploymentsClient.List(metav1.ListOptions{LabelSelector: "app=submariner-engine"})
		if err == nil && len(deployments.Items) > 0 {
			for _, deploy := range deployments.Items {
				if deploy.Status.ReadyReplicas == int32(cl.NumGateways) {
					log.Infof("Submariner engine successfully deployed to %s, ready replicas: %v", cl.ClusterName, deploy.Status.ReadyReplicas)
					cancel()
					wg.Done()
				} else if deploy.Status.ReadyReplicas < int32(cl.NumGateways) {
					log.Infof("Still waiting for submariner engine deployment %s...", cl.ClusterName)
				}
			}
		} else if err != nil {
			log.Infof("Still waiting for submariner engine deployment %s %v", cl.ClusterName, err)
		}
	}, 60*time.Second, submarinerContext.Done())
	err = submarinerContext.Err()
	if err != nil && err != context.Canceled {
		log.Fatalf("Error waiting for submariner engine deployment %s %s", cl.ClusterName, err)
		wg.Done()

	}
}

//Create tiller deployment
func CreateTillerDeployment(cls []ClusterData) {
	for _, cl := range cls {
		currentDir, _ := os.Getwd()
		kubeConfigFile := filepath.Join(currentDir, ".config", cl.ClusterName, "auth", "kubeconfig")
		deployFile := filepath.Join(currentDir, "deploy/tiller/tillerdeploy.json")
		config, err := clientcmd.BuildConfigFromFlags("", kubeConfigFile)
		if err != nil {
			panic(err.Error())
		}

		clientset, err := kubernetes.NewForConfig(config)
		if err != nil {
			panic(err.Error())
		}

		file, err := os.Open(deployFile)
		if err != nil {
			panic(err.Error())
		}
		dec := json.NewDecoder(file)

		var dep extensionsv1beta1.Deployment
		err = dec.Decode(&dep)
		if err != nil {
			log.Fatal(err)
		}

		deploymentsClient := clientset.ExtensionsV1beta1().Deployments("kube-system")

		result, err := deploymentsClient.Create(&dep)
		if err != nil && strings.Contains(err.Error(), "already exists") {
			log.Infof("%s %s", err.Error(), cl.ClusterName)
		} else if err != nil {
			log.Fatalf("%s %s", err, cl.ClusterName)
		} else {
			log.Infof("Tiller deployed for %s at: %s.", cl.ClusterName, result.CreationTimestamp)
		}
	}
}

//Create tiller service account
func CreateTillerServiceAccount(cls []ClusterData) {
	for _, cl := range cls {
		currentDir, _ := os.Getwd()
		kubeConfigFile := filepath.Join(currentDir, ".config", cl.ClusterName, "auth", "kubeconfig")
		deployFile := filepath.Join(currentDir, "deploy/tiller/serviceaccount.json")
		config, err := clientcmd.BuildConfigFromFlags("", kubeConfigFile)
		if err != nil {
			panic(err.Error())
		}

		clientset, err := kubernetes.NewForConfig(config)
		if err != nil {
			panic(err.Error())
		}

		file, err := os.Open(deployFile)
		if err != nil {
			panic(err.Error())
		}
		dec := json.NewDecoder(file)

		var sa corev1.ServiceAccount
		err = dec.Decode(&sa)
		if err != nil {
			log.Fatal(err)
		}

		result, err := clientset.CoreV1().ServiceAccounts("kube-system").Create(&sa)
		if err != nil && strings.Contains(err.Error(), "already exists") {
			log.Infof("%s %s", err.Error(), cl.ClusterName)
		} else if err != nil {
			log.Fatalf("%s %s", err, cl.ClusterName)
		} else {
			log.Infof("Tiller service account created for %s at: %s", cl.ClusterName, result.CreationTimestamp)
		}
	}
}

//Create tiller cluster role binding
func CreateTillerClusterRoleBinding(cls []ClusterData) {
	for _, cl := range cls {
		currentDir, _ := os.Getwd()
		kubeConfigFile := filepath.Join(currentDir, ".config", cl.ClusterName, "auth", "kubeconfig")
		deployFile := filepath.Join(currentDir, "deploy/tiller/clusterrolebinding.json")
		config, err := clientcmd.BuildConfigFromFlags("", kubeConfigFile)
		if err != nil {
			panic(err.Error())
		}

		clientset, err := kubernetes.NewForConfig(config)
		if err != nil {
			panic(err.Error())
		}

		file, err := os.Open(deployFile)
		if err != nil {
			panic(err.Error())
		}
		dec := json.NewDecoder(file)

		var crb rbacv1.ClusterRoleBinding
		err = dec.Decode(&crb)
		if err != nil {
			log.Fatal(err)
		}

		result, err := clientset.RbacV1().ClusterRoleBindings().Create(&crb)
		if err != nil && strings.Contains(err.Error(), "already exists") {
			log.Infof("%s %s", err.Error(), cl.ClusterName)
		} else if err != nil {
			log.Fatalf("%s %s", err, cl.ClusterName)
		} else {
			log.Infof("Tiller cluster role binding created for %s at: %s", cl.ClusterName, result.CreationTimestamp)
		}
	}
}

//Copy existing kubeconfig files with required changes
func ModifyKubeConfigFiles(cls []ClusterData) {
	log.Info("Modifying kubeconfig files.")

	var kubeconf KubeConfig

	for _, cl := range cls {
		currentDir, _ := os.Getwd()
		kubeFile := filepath.Join(currentDir, ".config", cl.ClusterName, "auth", "kubeconfig")
		newKubeFile := filepath.Join(currentDir, ".config", cl.ClusterName, "auth", "kubeconfig-dev")
		kubefile, err := ioutil.ReadFile(kubeFile)
		if err != nil {
			log.Fatal(err)
		}

		err = yaml.Unmarshal(kubefile, &kubeconf)
		if err != nil {
			log.Fatal(err)
		}

		kubeconf.CurrentContext = cl.ClusterName
		kubeconf.Contexts[0].Name = cl.ClusterName
		kubeconf.Contexts[0].Context.Cluster = cl.ClusterName
		kubeconf.Contexts[0].Context.User = cl.ClusterName
		kubeconf.Clusters[0].Name = cl.ClusterName
		kubeconf.Users[0].Name = cl.ClusterName

		d, err := yaml.Marshal(&kubeconf)
		if err != nil {
			log.Fatalf("error: %v", err)
		}

		err = ioutil.WriteFile(newKubeFile, d, 0644)
		if err != nil {
			log.Fatal(err)
		}
		log.Debugf("Modifying %s", kubeFile)
	}
}

//Extract infra details from metadata.json
func ExtractInfraDetails(cl ClusterData) []string {
	currentDir, _ := os.Getwd()
	metaJson := filepath.Join(currentDir, ".config", cl.ClusterName, "metadata.json")
	jsonFile, err := os.Open(metaJson)
	if err != nil {
		log.Fatal(err)
	}

	byteValue, err := ioutil.ReadAll(jsonFile)
	if err != nil {
		log.Fatal(err)
	}

	var result map[string]interface{}
	err = json.Unmarshal([]byte(byteValue), &result)
	if err != nil {
		log.Fatal(err)
	}

	infraDetails := []string{result["infraID"].(string), result["clusterID"].(string), result["clusterName"].(string)}
	return infraDetails
}

//Run worker creation terraform module
func CreateTerraformWorkers(wg *sync.WaitGroup, cl ClusterData, ac string) {
	var status string
	if ac == "destroy" {
		status = "destroyed"
		log.Infof("Destroying workers for %s.", cl.ClusterName)
	} else {
		status = "created"
		log.Infof("Creating workers for %s.", cl.ClusterName)
	}

	results := ExtractInfraDetails(cl)
	cmdName := "./bin/terraform"
	cmdArgs := []string{
		ac, "-target", "module." + cl.ClusterName + "-workers",
		"-var", "aws_region=" + cl.Region,
		"-var", "infra_id=" + results[0],
		"-var", "vpc_cidr=" + cl.VpcCidr,
		"-var", "dns_domain=" + cl.DNSDomain,
		"-var", "num_worker_nodes=" + strconv.Itoa(cl.NumWorkers),
		"-var", "num_subm_gateway_nodes=" + strconv.Itoa(cl.NumGateways),
		"-state", "tf/state/" + "terraform-" + cl.ClusterName + "-workers.tfstate",
		"-auto-approve",
	}

	cmd := exec.Command(cmdName, cmdArgs...)
	buf := &bytes.Buffer{}
	cmd.Stdout = buf
	cmd.Stderr = buf

	err := cmd.Start()
	if err != nil {
		log.Errorf("Error starting terraform: %s %s\n %s", cl.ClusterName, err, buf.String())
	}

	err = cmd.Wait()
	if err != nil {
		log.Errorf("Error waiting for workers infra: %s %s\n %s", cl.ClusterName, err, buf.String())
	}

	log.WithFields(log.Fields{
		"cluster": cl.ClusterName,
	}).Debugf("%s %s", cl.ClusterName, buf.String())

	output := strings.Split(buf.String(), "\n")
	log.Infof("Workers were %s for %s: %s", status, cl.ClusterName, output[len(output)-2])
	wg.Done()

}

//Run infra creation terraform module
func CreateTerraformInfra(wg *sync.WaitGroup, cl ClusterData, ac string) {
	var status string
	if ac == "destroy" {
		status = "destroyed"
		log.Infof("Destroying infra for %s.", cl.ClusterName)
	} else {
		status = "created"
		log.Infof("Creating infra for %s.", cl.ClusterName)
	}

	infraDetails := ExtractInfraDetails(cl)
	cmdName := "./bin/terraform"
	cmdArgs := []string{
		ac, "-target", "module." + cl.ClusterName + "-infra",
		"-var", "aws_region=" + cl.Region,
		"-var", "infra_id=" + infraDetails[0],
		"-var", "vpc_cidr=" + cl.VpcCidr,
		"-var", "dns_domain=" + cl.DNSDomain,
		"-var", "num_master_nodes=" + strconv.Itoa(cl.NumMasters),
		"-state", "tf/state/" + "terraform-" + cl.ClusterName + "-infra.tfstate",
		"-auto-approve",
	}

	cmd := exec.Command(cmdName, cmdArgs...)
	buf := &bytes.Buffer{}
	cmd.Stdout = buf
	cmd.Stderr = buf

	err := cmd.Start()
	if err != nil {
		log.Errorf("Error starting terraform: %s %s\n %s", cl.ClusterName, err, buf.String())
	}

	err = cmd.Wait()
	if err != nil {
		log.Errorf("Error waiting for infra: %s %s\n %s", cl.ClusterName, err, buf.String())
	}

	log.WithFields(log.Fields{
		"cluster": cl.ClusterName,
	}).Debugf("%s %s", cl.ClusterName, buf.String())

	output := strings.Split(buf.String(), "\n")
	log.Infof("Infra was %s for %s: %s", status, cl.ClusterName, output[len(output)-2])
	wg.Done()

}

//Run bootstrap creation terraform module
func CreateTerraformBootStrap(wg *sync.WaitGroup, cl ClusterData) {
	infraDetails := ExtractInfraDetails(cl)
	consoleUrl := []string{"https://console-openshift-console.apps", infraDetails[2], cl.DNSDomain}
	http.DefaultTransport.(*http.Transport).TLSClientConfig = &tls.Config{InsecureSkipVerify: true}
	_, err := http.Get(strings.Join(consoleUrl, "."))
	if err != nil {
		log.Infof("Creating bootstrap infra for %s.", cl.ClusterName)
		cmdName := "./bin/terraform"
		cmdArgs := []string{
			"apply", "-target", "module." + cl.ClusterName + "-bootstrap",
			"-var", "aws_region=" + cl.Region,
			"-var", "infra_id=" + infraDetails[0],
			"-var", "vpc_cidr=" + cl.VpcCidr,
			"-var", "dns_domain=" + cl.DNSDomain,
			"-state", "tf/state/" + "terraform-" + cl.ClusterName + "-bootstrap.tfstate",
			"-auto-approve",
		}

		cmd := exec.Command(cmdName, cmdArgs...)
		buf := &bytes.Buffer{}
		cmd.Stdout = buf
		cmd.Stderr = buf

		err := cmd.Start()
		if err != nil {
			log.Errorf("Error starting terraform: %s %s\n %s", cl.ClusterName, err, buf.String())
		}

		err = cmd.Wait()
		if err != nil {
			log.Errorf("Error waiting for bootstrap infra: %s %s\n %s", cl.ClusterName, err, buf.String())
		}

		log.WithFields(log.Fields{
			"cluster": cl.ClusterName,
		}).Debugf("%s %s", cl.ClusterName, buf.String())

		output := strings.Split(buf.String(), "\n")
		log.Infof("Bootstrap infra was created for %s: %s", cl.ClusterName, output[len(output)-2])
		wg.Done()
	} else {
		log.Infof("Openshift console is available, skipping bootstrap for %s.", cl.ClusterName)
		wg.Done()
	}
}

//Run bootstrap deletion
func DestroyTerraformBootStrap(wg *sync.WaitGroup, cl ClusterData) {
	log.Infof("Destroying bootstrap infra for %s.", cl.ClusterName)
	infraDetails := ExtractInfraDetails(cl)
	cmdName := "./bin/terraform"
	cmdArgs := []string{
		"destroy", "-target", "module." + cl.ClusterName + "-bootstrap",
		"-var", "aws_region=" + cl.Region,
		"-var", "infra_id=" + infraDetails[0],
		"-var", "vpc_cidr=" + cl.VpcCidr,
		"-var", "dns_domain=" + cl.DNSDomain,
		"-state", "tf/state/" + "terraform-" + cl.ClusterName + "-bootstrap.tfstate",
		"-auto-approve",
	}

	cmd := exec.Command(cmdName, cmdArgs...)
	buf := &bytes.Buffer{}
	cmd.Stdout = buf
	cmd.Stderr = buf

	err := cmd.Start()
	if err != nil {
		log.Errorf("Error starting terraform: %s %s\n %s", cl.ClusterName, err, buf.String())
	}

	err = cmd.Wait()
	if err != nil {
		log.Errorf("Error waiting for bootstrap infra: %s %s\n %s", cl.ClusterName, err, buf.String())
	}

	log.WithFields(log.Fields{
		"cluster": cl.ClusterName,
	}).Debugf("%s %s", cl.ClusterName, buf.String())

	output := strings.Split(buf.String(), "\n")
	log.Infof("Bootstrap infra was destroyed for %s: %s", cl.ClusterName, output[len(output)-2])
	wg.Done()
}

//Wait for ocp4 install completion
func WaitForInstallComplete(wg *sync.WaitGroup, cl ClusterData) {
	log.Infof("Waiting for installation completion %s. Up to 30 minutes.", cl.ClusterName)
	currentDir, _ := os.Getwd()
	configDir := filepath.Join(currentDir, ".config", cl.ClusterName)
	cmdName := "./bin/openshift-install"
	cmdArgs := []string{"wait-for", "install-complete", "--dir", configDir}

	cmd := exec.Command(cmdName, cmdArgs...)
	buf := &bytes.Buffer{}
	cmd.Stdout = buf
	cmd.Stderr = buf

	err := cmd.Start()
	if err != nil {
		log.Fatalf("Error starting Cmd: %s %s\n%s", err, cl.ClusterName, buf.String())
	}

	err = cmd.Wait()
	if err != nil {
		log.Fatalf("Error waiting for installation completion: %s %s\n%s", err, cl.ClusterName, buf.String())
	}

	log.WithFields(log.Fields{
		"cluster": cl.ClusterName,
	}).Debugf("%s %s", cl.ClusterName, buf.String())

	log.Infof("Openshift was installed on %s. Connection details: %s", cl.ClusterName, configDir+"/.openshift_install.log")
	wg.Done()
}

//Wait for bootstrap completion
func WaitForBootstrap(wg *sync.WaitGroup, cl ClusterData) {
	currentDir, _ := os.Getwd()
	configDir := filepath.Join(currentDir, ".config", cl.ClusterName)
	log.Infof("Waiting for bootstrap completion %s. Up to 60 minutes. Detailed log: %s", cl.ClusterName, configDir+"/.openshift_install.log")
	cmdName := "./bin/openshift-install"
	cmdArgs := []string{"wait-for", "bootstrap-complete", "--dir", configDir}

	cmd := exec.Command(cmdName, cmdArgs...)
	buf := &bytes.Buffer{}
	cmd.Stdout = buf
	cmd.Stderr = buf

	err := cmd.Start()
	if err != nil {
		log.Fatalf("Error starting Cmd: %s %s\n%s", err, cl.ClusterName, buf.String())
	}

	err = cmd.Wait()
	if err != nil {
		log.Fatalf("Error waiting for bootstrap: %s %s\n%s", err, cl.ClusterName, buf.String())
	}

	log.WithFields(log.Fields{
		"cluster": cl.ClusterName,
	}).Debugf("%s %s", cl.ClusterName, buf.String())

	output := strings.Split(buf.String(), "\n")
	log.Infof("Bootstrap was complete for %s: %s", cl.ClusterName, output[len(output)-2])
	wg.Done()
}

//Generate ignition configs
func GenerateIgnitionConfigs(wg *sync.WaitGroup, cl ClusterData) {
	currentDir, _ := os.Getwd()
	configDir := filepath.Join(currentDir, ".config", cl.ClusterName)
	cmdName := "./bin/openshift-install"
	cmdArgs := []string{"create", "ignition-configs", "--dir", configDir, "--log-level", "debug"}

	cmd := exec.Command(cmdName, cmdArgs...)
	buf := &bytes.Buffer{}
	cmd.Stdout = buf
	cmd.Stderr = buf

	err := cmd.Start()
	if err != nil {
		log.Fatalf("Error starting Cmd: %s %s\n%s", err, cl.ClusterName, buf.String())
	}

	err = cmd.Wait()
	if err != nil {
		log.Fatalf("Error waiting for Cmd: %s %s\n%s", err, cl.ClusterName, buf.String())
	}

	log.WithFields(log.Fields{
		"cluster": cl.ClusterName,
	}).Debugf("%s %s", cl.ClusterName, buf.String())
	wg.Done()
}

//Remove machine set files
func RemoveMachineSets(cls []ClusterData) {
	currentDir, _ := os.Getwd()
	for _, cl := range cls {
		configDir := filepath.Join(currentDir, ".config", cl.ClusterName)
		globs := []string{"openshift/99_openshift-cluster-api_master-machines-*.yaml", "openshift/99_openshift-cluster-api_worker-machineset-*.yaml"}

		for _, gl := range globs {
			files, err := filepath.Glob(filepath.Join(configDir, gl))
			if err != nil {
				log.Fatal(err)
			}
			for _, f := range files {
				log.Debugf("Removing %s", f)
				if err := os.Remove(f); err != nil {
					log.Fatal(err)
				}
			}
		}
	}
}

//Generate manifests
func GenerateManifests(wg *sync.WaitGroup, cl ClusterData) {
	currentDir, _ := os.Getwd()
	configDir := filepath.Join(currentDir, ".config", cl.ClusterName)
	cmdName := "./bin/openshift-install"
	cmdArgs := []string{"create", "manifests", "--dir", configDir, "--log-level", "debug"}

	cmd := exec.Command(cmdName, cmdArgs...)
	buf := &bytes.Buffer{}
	cmd.Stdout = buf
	cmd.Stderr = buf

	err := cmd.Start()
	if err != nil {
		log.Fatalf("Error starting Cmd: %s %s\n%s", err, cl.ClusterName, buf.String())
	}

	err = cmd.Wait()
	if err != nil {
		log.Fatalf("Error waiting for manifests generation: %s %s\n%s", err, cl.ClusterName, buf.String())
	}

	log.WithFields(log.Fields{
		"cluster": cl.ClusterName,
	}).Debugf("%s %s", cl.ClusterName, buf.String())
	wg.Done()
}

//Generate config dirs
func GenerateConfigDirs(cls []ClusterData) {
	currentDir, _ := os.Getwd()

	for _, cl := range cls {
		configDir := filepath.Join(currentDir, ".config", cl.ClusterName)
		_ = os.MkdirAll(configDir, os.ModePerm)

		log.Debugf("Config directories for %s created.", cl.ClusterName)
	}
}

//Generate config files
func GenerateConfigFiles(cls []ClusterData, auth AuthData) {
	currentDir, _ := os.Getwd()

	c, err := user.Current()
	if err != nil {
		log.Fatal(err)
	}

	t, err := template.ParseFiles(filepath.Join(currentDir, "tpl", "install-config.yaml"))
	if err != nil {
		log.Error(err)
		return
	}

	for _, cl := range cls {
		if _, err := os.Stat(filepath.Join(currentDir, ".config", cl.ClusterName, "metadata.json")); os.IsNotExist(err) {
			configFile := filepath.Join(currentDir, ".config", cl.ClusterName, "install-config.yaml")
			f, err := os.Create(configFile)
			if err != nil {
				log.Fatal("create file: ", err)
				return
			}

			cl.ClusterName = c.Username + "-" + cl.ClusterName

			type combined struct {
				ClusterData
				AuthData
			}

			err = t.Execute(f, combined{cl, auth})
			if err != nil {
				log.Fatal("execute: ", err)
				return
			}

			if err := f.Close(); err != nil {
				log.Fatal(err)
			}

			log.Debugf("Config files for %s generated.", cl.ClusterName)
		} else {
			log.Debugf("metadata.json exists for %s, skipping install config creation.", cl.ClusterName)
		}
	}
}

//Parse the main config file
func ParseConfigFile() ([]ClusterData, AuthData, HelmData, OpenshiftData, error) {

	var cluster1 ClusterData
	err := viper.UnmarshalKey("cluster1", &cluster1)
	if err != nil {
		log.Fatal(err)
		return nil, AuthData{}, HelmData{}, OpenshiftData{}, err
	}

	var cluster2 ClusterData
	err = viper.UnmarshalKey("cluster2", &cluster2)
	if err != nil {
		log.Fatal(err)
		return nil, AuthData{}, HelmData{}, OpenshiftData{}, err
	}

	var cluster3 ClusterData
	err = viper.UnmarshalKey("cluster3", &cluster3)
	if err != nil {
		log.Fatal(err)
		return nil, AuthData{}, HelmData{}, OpenshiftData{}, err
	}

	var auth AuthData
	err = viper.UnmarshalKey("authentication", &auth)
	if err != nil {
		log.Fatal(err)
		return nil, AuthData{}, HelmData{}, OpenshiftData{}, err
	}

	var helm HelmData
	err = viper.UnmarshalKey("helm", &helm)
	if err != nil {
		log.Fatal(err)
		return nil, AuthData{}, HelmData{}, OpenshiftData{}, err
	}

	var openshift OpenshiftData
	err = viper.UnmarshalKey("openshift", &openshift)
	if err != nil {
		log.Fatal(err)
		return nil, AuthData{}, HelmData{}, OpenshiftData{}, err
	}

	cls := []ClusterData{cluster1, cluster2, cluster3}

	return cls, auth, helm, openshift, nil
}

var clusterCmd = &cobra.Command{
	Use:   "clusters",
	Short: "Create multiple OCP4 clusters",
	Run: func(cmd *cobra.Command, args []string) {

		if Debug {
			log.SetReportCaller(true)
			log.SetLevel(log.DebugLevel)
		}

		clusters, authConfig, helmConfig, openshiftConfig, err := ParseConfigFile()
		if err != nil {
			log.Fatal(err)
		}

		var wg sync.WaitGroup

		log.Infof("Getting required tools...")
		GetDependencies(openshiftConfig)

		log.Infof("Generating install configs, manifests and ignition configs...")
		GenerateConfigDirs(clusters)
		GenerateConfigFiles(clusters, authConfig)

		wg.Add(len(clusters))
		go GenerateManifests(&wg, clusters[0])
		go GenerateManifests(&wg, clusters[1])
		go GenerateManifests(&wg, clusters[2])
		wg.Wait()

		RemoveMachineSets(clusters)

		wg.Add(len(clusters))
		go GenerateIgnitionConfigs(&wg, clusters[0])
		go GenerateIgnitionConfigs(&wg, clusters[1])
		go GenerateIgnitionConfigs(&wg, clusters[2])
		wg.Wait()

		TerraformInit()

		wg.Add(len(clusters))
		go CreateTerraformInfra(&wg, clusters[0], "apply")
		go CreateTerraformInfra(&wg, clusters[1], "apply")
		go CreateTerraformInfra(&wg, clusters[2], "apply")
		wg.Wait()

		wg.Add(len(clusters))
		go CreateTerraformBootStrap(&wg, clusters[0])
		go CreateTerraformBootStrap(&wg, clusters[1])
		go CreateTerraformBootStrap(&wg, clusters[2])
		wg.Wait()

		wg.Add(len(clusters))
		go WaitForBootstrap(&wg, clusters[0])
		go WaitForBootstrap(&wg, clusters[1])
		go WaitForBootstrap(&wg, clusters[2])
		wg.Wait()

		wg.Add(len(clusters))
		go CreateTerraformWorkers(&wg, clusters[0], "apply")
		go CreateTerraformWorkers(&wg, clusters[1], "apply")
		go CreateTerraformWorkers(&wg, clusters[2], "apply")
		wg.Wait()

		wg.Add(len(clusters))
		go WaitForInstallComplete(&wg, clusters[0])
		go WaitForInstallComplete(&wg, clusters[1])
		go WaitForInstallComplete(&wg, clusters[2])
		wg.Wait()

		wg.Add(len(clusters))
		go DestroyTerraformBootStrap(&wg, clusters[0])
		go DestroyTerraformBootStrap(&wg, clusters[1])
		go DestroyTerraformBootStrap(&wg, clusters[2])
		wg.Wait()

		CreateTillerServiceAccount(clusters)
		CreateTillerClusterRoleBinding(clusters)
		CreateTillerDeployment(clusters)
		WaitForTillerDeployment(clusters)
		HelmInit(helmConfig.HelmRepo.URL)
		InstallSubmarinerBroker(clusters[0], helmConfig.Broker.Namespace)

		wg.Add(len(clusters) - 1)
		go LabelGatewayNodes(&wg, clusters[1])
		go LabelGatewayNodes(&wg, clusters[2])
		wg.Wait()

		wg.Add(len(clusters) - 1)
		go AddSubmarinerSecurityContext(&wg, clusters[1])
		go AddSubmarinerSecurityContext(&wg, clusters[2])
		wg.Wait()

		psk := GeneratePsk()

		wg.Add(len(clusters) - 1)
		go InstallSubmarinerGateway(&wg, clusters[1], clusters[0], helmConfig, psk)
		go InstallSubmarinerGateway(&wg, clusters[2], clusters[0], helmConfig, psk)
		wg.Wait()

		wg.Add(len(clusters) - 1)
		go WaitForSubmarinerDeployment(&wg, clusters[1], helmConfig)
		go WaitForSubmarinerDeployment(&wg, clusters[2], helmConfig)
		wg.Wait()

		ModifyKubeConfigFiles(clusters)
		log.Infof("Kubeconfigs: export KUBECONFIG=$(echo $(git rev-parse --show-toplevel)/.config/cluster{1..3}/auth/kubeconfig-dev | sed 's/ /:/g')")
	},
}

func init() {
	var createCmd = &cobra.Command{Use: "create", Short: "Create resources"}
	rootCmd.AddCommand(createCmd)
	createCmd.AddCommand(clusterCmd)
}
