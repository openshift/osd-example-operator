package tests

import (
	"log"

	"github.com/mrsantamaria/osde2e-example-test-harness/pkg/metadata"
	"github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	"k8s.io/apiextensions-apiserver/pkg/client/clientset/clientset"
	v1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/rest"
)

var _ = ginkgo.Describe("Prow Operator Tests", func() {
	defer ginkgo.GinkgoRecover()
	config, err := rest.InClusterConfig()

	if err != nil {
		panic(err)
	}

	ginkgo.It("prowjobs.prow.k8s.io CRD exists", func() {
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
})
