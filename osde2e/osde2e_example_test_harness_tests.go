// DO NOT REMOVE TAGS BELOW. IF ANY NEW TEST FILES ARE CREATED UNDER /osde2e, PLEASE ADD THESE TAGS TO THEM IN ORDER TO BE EXCLUDED FROM UNIT TESTS. //go:build osde2e
//go:build osde2e
// +build osde2e

package osde2etests

import (
	"github.com/onsi/ginkgo/v2"
	"github.com/onsi/gomega"
)

var _ = ginkgo.Describe("osde2e-example-test-harness", func() {
	ginkgo.It("Makes simple assertion", func() {
		gomega.Expect(1).Should(gomega.Equal(1), "one should equal one")
	})

})
