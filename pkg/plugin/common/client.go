package common

import (
	"fmt"

	"github.com/konpyutaika/nifikop/api/v1alpha1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/kubernetes/scheme"
	_ "k8s.io/client-go/plugin/pkg/client/auth"
	"k8s.io/client-go/tools/clientcmd"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/apiutil"
)

// NewClient returns a new controller-runtime client instance
func NewClient(clientConfig clientcmd.ClientConfig) (client.Client, error) {
	restConfig, err := clientConfig.ClientConfig()
	if err != nil {
		return nil, fmt.Errorf("unable to get rest client config: %w", err)
	}

	// Create the mapper provider
	mapper, err := apiutil.NewDiscoveryRESTMapper(restConfig)
	if err != nil {
		return nil, fmt.Errorf("unable to to instantiate mapper: %w", err)
	}

	// Register NifiKop scheme
	if err = v1alpha1.AddToScheme(scheme.Scheme); err != nil {
		return nil, fmt.Errorf("unable register DatadogAgent apis: %w", err)
	}

	// // Create the Client for Read/Write operations.
	var newClient client.Client
	newClient, err = client.New(restConfig, client.Options{Scheme: scheme.Scheme, Mapper: mapper})
	if err != nil {
		return nil, fmt.Errorf("unable to instantiate client: %w", err)
	}

	return newClient, nil
}

// NewClientset returns a new client-go instance
func NewClientset(clientConfig clientcmd.ClientConfig) (*kubernetes.Clientset, error) {
	restConfig, err := clientConfig.ClientConfig()
	if err != nil {
		return nil, fmt.Errorf("unable to get rest client config: %w", err)
	}

	clientset, err := kubernetes.NewForConfig(restConfig)
	if err != nil {
		return nil, fmt.Errorf("unable to instantiate client: %w", err)
	}

	return clientset, nil
}
