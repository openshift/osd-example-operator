// DO NOT REMOVE TAGS BELOW. IF ANY NEW TEST FILES ARE CREATED UNDER /test/e2e, PLEASE ADD THESE TAGS TO THEM IN ORDER TO BE EXCLUDED FROM UNIT TESTS.
//go:build osde2e

package osde2etests

import (
	"context"
	"os"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	ocme2e "github.com/openshift/osde2e-common/pkg/clients/ocm"
)

var _ = Describe("osd-example-operator", func() {
	It("asserts success", func(ctx context.Context) {
		Expect(true).To(BeTrue(), "True should be true")
	})

	It("should connect to stage ocm client", func(ctx context.Context) {
		By("Getting ocm creds")
		clientID := os.Getenv("OCM_CLIENT_ID")
		clientSecret := os.Getenv("OCM_CLIENT_SECRET")
		Expect(clientID).NotTo(BeEmpty(), "OCM_CLIENT_ID must be set")
		Expect(clientSecret).NotTo(BeEmpty(), "OCM_CLIENT_SECRET must be set")
		ocmEnv := ocme2e.Stage
		_, err := ocme2e.New(ctx, "", clientID, clientSecret, ocmEnv)
		Expect(err).ShouldNot(HaveOccurred(), "Unable to setup stage OCM Client")
	})

	// Failing test for log analysis demo
	// It("should fail on purpose", func() {
	// 	fmt.Println("Running Intentional Failure Test")
	// 	Expect(true).To(BeFalse(), "This test is designed to fail intentionally")
	// })
})
