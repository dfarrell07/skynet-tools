package cmd

import (
	"bytes"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
)

func DeleteCluster(wg *sync.WaitGroup, cl ClusterData) {
	log.Infof("Deleting resources for %s. Please be patient. Up to 45 minutes...", cl.ClusterName)
	currentDir, _ := os.Getwd()
	configDir := filepath.Join(currentDir, ".config", cl.ClusterName)
	cmdName := "./bin/openshift-install"
	cmdArgs := []string{"destroy", "cluster", "--dir", configDir, "--log-level", "debug"}

	cmd := exec.Command(cmdName, cmdArgs...)
	buf := &bytes.Buffer{}
	cmd.Stdout = buf
	cmd.Stderr = buf

	err := cmd.Start()
	if err != nil {
		log.Fatalf("Error starting deletion: %s %s\n%s", err, cl.ClusterName, buf.String())
	}

	err = cmd.Wait()
	if err != nil {
		log.Fatalf("Error waiting for deletion: %s %s\n%s", err, cl.ClusterName, buf.String())
	}

	glob := "terraform-" + cl.ClusterName + "-*"
	files, err := filepath.Glob(filepath.Join("tf", "state", glob))
	if err != nil {
		log.Fatal(err)
	}
	for _, f := range files {
		log.Debugf("Removing %s", f)
		if err := os.Remove(f); err != nil {
			log.Fatal(err)
		}
	}

	log.WithFields(log.Fields{
		"cluster": cl.ClusterName,
	}).Debugf("%s %s", cl.ClusterName, buf.String())
	log.Infof("Resources for %s were removed.", cl.ClusterName)
	wg.Done()
}

var destroyClustersCmd = &cobra.Command{
	Use:   "clusters",
	Short: "Destroy cluster resources",
	Run: func(cmd *cobra.Command, args []string) {

		if Debug {
			log.SetReportCaller(true)
			log.SetLevel(log.DebugLevel)
		}

		clusters, _, _, openshiftConfig, err := ParseConfigFile()
		if err != nil {
			log.Fatal(err)
		}

		GetDependencies(openshiftConfig)

		var wg sync.WaitGroup
		wg.Add(len(clusters))
		for i := range clusters {
			go DeleteCluster(&wg, clusters[i])
		}
		wg.Wait()

	},
}

func init() {
	var destroyCmd = &cobra.Command{Use: "destroy", Short: "Destroy resources"}
	rootCmd.AddCommand(destroyCmd)
	destroyCmd.AddCommand(destroyClustersCmd)
}
