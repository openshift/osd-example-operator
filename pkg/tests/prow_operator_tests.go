package tests

import (
	"log"

	"github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	"github.com/openshift/osde2e-example-test-harness/pkg/metadata"

	"k8s.io/apiextensions-apiserver/pkg/client/clientset/clientset"
	v1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/rest"
)

// Make sure the CRD exists. Using crd name for reference-addon used in the example.
var crdName = "referenceaddons.reference.addons.managed.openshift.io"

var _ = ginkgo.Describe("Example Addon Tests", func() {
	defer ginkgo.GinkgoRecover()
	config, err := rest.InClusterConfig()

	if err != nil {
		panic(err)
	}

	ginkgo.It("referenceaddons.reference.addons.managed.openshift.io CRD exists", func() {
		apiextensions, err := clientset.NewForConfig(config)
		Expect(err).NotTo(HaveOccurred())

		result, err := apiextensions.ApiextensionsV1().CustomResourceDefinitions().Get(crdName, v1.GetOptions{})

		if err != nil {
			log.Printf("CRD %v not found: %v", crdName, err.Error())
			metadata.Instance.FoundCRD = false
		} else {
			log.Printf("CRD %v found: %v", crdName, result)
			metadata.Instance.FoundCRD = true
		}

		Expect(err).NotTo(HaveOccurred())
	}, float64(30))
})
