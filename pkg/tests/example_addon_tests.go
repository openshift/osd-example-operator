package tests

import (
	"log"

	"github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	"github.com/openshift/osde2e-example-test-harness/pkg/metadata"
	apiextclientset "k8s.io/apiextensions-apiserver/pkg/client/clientset/clientset"
	v1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

var _ = ginkgo.Describe("Example Addon Tests", func() {
	var config *rest.Config

	ginkgo.BeforeEach(func() {
		var err error
		config, err = rest.InClusterConfig()
		Expect(err).NotTo(HaveOccurred(), "unable to load in cluster config")
	})

	ginkgo.It("CRD addons.addons.managed.openshift.io exists", func() {
		client, err := apiextclientset.NewForConfig(config)
		Expect(err).NotTo(HaveOccurred(), "failed to create clientset")

		// Make sure the CRD exists
		result, err := client.ApiextensionsV1().CustomResourceDefinitions().Get("addons.addons.managed.openshift.io", v1.GetOptions{})
		if err != nil {
			log.Printf("CRD not found: %v", err.Error())
			metadata.Instance.FoundCRD = false
		} else {
			log.Printf("CRD found: %v", result.GetName())
			metadata.Instance.FoundCRD = true
		}

		Expect(err).NotTo(HaveOccurred(), "failed to get the crd")
	})

	ginkgo.It("Example passthrough secret exists", func() {
		k8s, err := kubernetes.NewForConfig(config)
		Expect(err).NotTo(HaveOccurred(), "unable to create client")

		namespace := "osde2e-ci-secrets"
		name := "ci-secrets"

		sec, err := k8s.CoreV1().Secrets(namespace).Get(name, v1.GetOptions{})
		Expect(err).NotTo(HaveOccurred(), "failed to fetch %s/%s secret", namespace, name)
		Expect(sec.Data).Should(HaveKey("testkey"))
	})
})
