package cmd

import (
	"fmt"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
	"os"
)

var cfgFile string
var Debug bool

// rootCmd represents the base command when called without any subcommands
var rootCmd = &cobra.Command{
	Use:   "ocpup",
	Short: "Create multiple OCP4 clusters and resources",
}

// Execute adds all child commands to the root command and sets flags appropriately.
// This is called by main.main(). It only needs to happen once to the rootCmd.
func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}

func init() {
	cobra.OnInitialize(initConfig)
	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default is ocpup.yaml)")
	rootCmd.PersistentFlags().BoolVarP(&Debug, "debug", "v", false, "debug mode")
}

// initConfig reads in config file and ENV variables if set.
func initConfig() {
	if cfgFile != "" {
		viper.SetConfigFile(cfgFile)
		log.Infof("Using config: %s", cfgFile)
	} else {
		viper.AddConfigPath(".")
		viper.SetConfigName("ocpup")
		log.Infof("Using config ocpup.yaml")

	}

	if err := viper.ReadInConfig(); err != nil {
		log.Fatalf("Can't read config: %s", err)
	}
}
