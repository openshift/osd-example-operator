package tests

import (
	"log"

	"github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	"github.com/openshift/osde2e-example-test-harness/pkg/metadata"

	"k8s.io/apiextensions-apiserver/pkg/client/clientset/clientset"
	v1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"

	"k8s.io/client-go/rest"
)

// Using Reference Addon for test
var crdName = "referenceaddons.reference.addons.managed.openshift.io"

var _ = ginkgo.Describe("Example Addon Tests", func() {
	defer ginkgo.GinkgoRecover()
	config, err := rest.InClusterConfig()

	if err != nil {
		panic(err)
	}

	ginkgo.It("Example CRD - "+crdName+" - exists", func() {
		apiextensions, err := clientset.NewForConfig(config)
		Expect(err).NotTo(HaveOccurred())

		// Make sure the CRD exists
		result, err := apiextensions.ApiextensionsV1().CustomResourceDefinitions().Get("addons.addons.managed.openshift.io", v1.GetOptions{})

		if err != nil {
			log.Printf("CRD not found: %v", err.Error())
			metadata.Instance.FoundCRD = false
		} else {
			log.Printf("CRD found: %v", result)
			metadata.Instance.FoundCRD = true
		}

		Expect(err).NotTo(HaveOccurred())
	}, float64(30))

	ginkgo.It("Example passthrough secret exists", func() {
		k8s, err := kubernetes.NewForConfig(config)
		Expect(err).NotTo(HaveOccurred())
		sec, err := k8s.CoreV1().Secrets("ci").Get("example-addon-secret", v1.GetOptions{})

		Expect(sec.Data["testkey"]).ToNot(BeNil())
		Expect(err).NotTo(HaveOccurred())

	}, float64(30))

})
