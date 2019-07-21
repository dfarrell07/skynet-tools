package cmd

import (
	"bytes"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
)

var (
	EngineImage     string
	RouteAgentImage string
	Reinstall       bool
)

// Delete submariner helm resources
func (cl ClusterData) DeleteSubmariner(ns string) {
	currentDir, _ := os.Getwd()
	kubeConfigFile := filepath.Join(currentDir, ".config", cl.ClusterName, "auth", "kubeconfig")
	cmdName := "./bin/helm"
	cmdArgs := []string{"del", "--purge", ns, "--kubeconfig", kubeConfigFile, "--debug"}

	cmd := exec.Command(cmdName, cmdArgs...)
	buf := &bytes.Buffer{}
	cmd.Stdout = buf
	cmd.Stderr = buf

	err := cmd.Start()
	if err != nil {
		log.Fatalf("Error starting helm: %s %s\n%s", cl.ClusterName, err, buf.String())
	}

	err = cmd.Wait()
	if err != nil && !strings.Contains(buf.String(), "not found") {
		log.Fatalf("Error waiting for helm: %s %s\n%s", cl.ClusterName, err, buf.String())
	}

	log.WithFields(log.Fields{
		"cluster": cl.ClusterName,
	}).Debugf("%s %s", cl.ClusterName, buf.String())
	log.Infof("✔ Submariner was removed from %s.", cl.ClusterName)
}

// Delete submariner CRDs
func (cl ClusterData) DeleteSubmarinerCrd() {
	currentDir, _ := os.Getwd()
	kubeConfigFile := filepath.Join(currentDir, ".config", cl.ClusterName, "auth", "kubeconfig")
	cmdName := "./bin/oc"
	cmdArgs := []string{
		"delete", "crd", "clusters.submariner.io", "endpoints.submariner.io",
		"--config", kubeConfigFile}

	cmd := exec.Command(cmdName, cmdArgs...)
	buf := &bytes.Buffer{}
	cmd.Stdout = buf
	cmd.Stderr = buf

	err := cmd.Start()
	if err != nil {
		log.Fatalf("Error starting helm: %s %s\n%s", cl.ClusterName, err, buf.String())
	}

	err = cmd.Wait()
	if err != nil && !strings.Contains(buf.String(), "not found") {
		log.Fatalf("Error waiting for helm: %s %s\n%s", cl.ClusterName, err, buf.String())
	}

	log.WithFields(log.Fields{
		"cluster": cl.ClusterName,
	}).Debugf("%s %s", cl.ClusterName, buf.String())
	log.Infof("✔ Submariner CRDs were removed from %s.", cl.ClusterName)
}

func (cl ClusterData) UpdateEngineDeployment(h HelmData) {
	currentDir, _ := os.Getwd()
	kubeConfigFile := filepath.Join(currentDir, ".config", cl.ClusterName, "auth", "kubeconfig")
	config, err := clientcmd.BuildConfigFromFlags("", kubeConfigFile)
	if err != nil {
		log.Fatal(err.Error())
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatal(err.Error())
		os.Exit(1)
	}

	log.Debugf("Updating engine deployment %s.", cl.ClusterName)
	deploymentsClient := clientset.AppsV1().Deployments(h.Engine.Namespace)

	result, err := deploymentsClient.Get("submariner", metav1.GetOptions{})
	if err != nil {
		log.Fatalf("Failed to get latest version of submariner engine deployment: %v %s", err, cl.ClusterName)
	}

	image := h.Engine.Image.Repository + ":" + h.Engine.Image.Tag

	result.Spec.Template.Spec.Containers[0].Image = image
	_, err = deploymentsClient.Update(result)
	if err != nil {
		log.Fatalf("Failed to update submariner engine deployment: %v %s", err, cl.ClusterName)
	}
	log.Infof("✔ Submariner engine deployment for %s was updated with image: %s.", cl.ClusterName, image)
}

func (cl ClusterData) UpdateRouteAgentDaemonSet(h HelmData) {
	currentDir, _ := os.Getwd()
	kubeConfigFile := filepath.Join(currentDir, ".config", cl.ClusterName, "auth", "kubeconfig")
	config, err := clientcmd.BuildConfigFromFlags("", kubeConfigFile)
	if err != nil {
		log.Fatal(err.Error())
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatal(err.Error())
		os.Exit(1)
	}

	log.Debugf("Updating route agent daemon set %s.", cl.ClusterName)
	dsClient := clientset.AppsV1().DaemonSets(h.RouteAgent.Namespace)

	result, err := dsClient.Get("submariner-routeagent", metav1.GetOptions{})
	if err != nil {
		log.Fatalf("Failed to get latest version of submariner route agent daemon set: %v %s", err, cl.ClusterName)
	}

	image := h.RouteAgent.Image.Repository + ":" + h.RouteAgent.Image.Tag

	result.Spec.Template.Spec.Containers[0].Image = image
	_, err = dsClient.Update(result)
	if err != nil {
		log.Fatalf("Failed to update submariner route agent daemon set: %v %s", err, cl.ClusterName)
	}
	log.Infof("✔ Submariner route agent daemon set for %s was updated with image: %s.", cl.ClusterName, image)
}

var updateSubmarinerCmd = &cobra.Command{
	Use:   "submariner",
	Short: "Update submariner deployment",
	Run: func(cmd *cobra.Command, args []string) {

		if Debug {
			log.SetReportCaller(true)
			log.SetLevel(log.DebugLevel)
		}

		clusters, _, helmConfig, openshiftConfig, err := ParseConfigFile()
		if err != nil {
			log.Fatal(err)
		}

		var wg sync.WaitGroup

		GetDependencies(openshiftConfig)

		if EngineImage != "" {
			helmConfig.Engine.Image.Repository = strings.Split(EngineImage, ":")[0]
			helmConfig.Engine.Image.Tag = strings.Split(EngineImage, ":")[1]
		}

		if RouteAgentImage != "" {
			helmConfig.RouteAgent.Image.Repository = strings.Split(RouteAgentImage, ":")[0]
			helmConfig.RouteAgent.Image.Tag = strings.Split(RouteAgentImage, ":")[1]
		}

		if Reinstall == true {
			log.Warn("Reinstalling submariner.")
			clusters[0].DeleteSubmariner(helmConfig.Broker.Namespace)
			clusters[0].DeleteSubmarinerCrd()

			for i := 1; i <= len(clusters[1:]); i++ {
				clusters[i].DeleteSubmariner(helmConfig.Engine.Namespace)
				clusters[i].DeleteSubmarinerCrd()
			}

			HelmInit(helmConfig.HelmRepo.URL)
			clusters[0].InstallSubmarinerBroker(helmConfig)

			psk := GeneratePsk()

			wg.Add(len(clusters[1:]))
			for i := 1; i <= len(clusters[1:]); i++ {
				go clusters[i].InstallSubmarinerGateway(&wg, clusters[0], helmConfig, psk)
			}
			wg.Wait()

			wg.Add(len(clusters[1:]))
			for i := 1; i <= len(clusters[1:]); i++ {
				go clusters[i].WaitForSubmarinerDeployment(&wg, helmConfig)
			}
			wg.Wait()
		} else {
			for i := 1; i <= len(clusters[1:]); i++ {
				clusters[i].UpdateEngineDeployment(helmConfig)
				clusters[i].UpdateRouteAgentDaemonSet(helmConfig)
			}
		}
	},
}

func init() {
	var updateCmd = &cobra.Command{Use: "update", Short: "Update resources"}
	rootCmd.AddCommand(updateCmd)
	updateCmd.AddCommand(updateSubmarinerCmd)
	updateSubmarinerCmd.Flags().StringVarP(&EngineImage, "engine", "", "", "engine image:tag")
	updateSubmarinerCmd.Flags().StringVarP(&RouteAgentImage, "routeagent", "", "", "route agent image:tag")
	updateSubmarinerCmd.Flags().BoolVarP(&Reinstall, "reinstall", "", false, "full submariner reinstall")
}
