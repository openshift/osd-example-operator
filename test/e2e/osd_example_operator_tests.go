// DO NOT REMOVE TAGS BELOW. IF ANY NEW TEST FILES ARE CREATED UNDER /test/e2e, PLEASE ADD THESE TAGS TO THEM IN ORDER TO BE EXCLUDED FROM UNIT TESTS.
//go:build osde2e

package osde2etests

import (
	"context"
	"fmt"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("osd-example-operator", func() {
	It("asserts success", func(ctx context.Context) {
		Expect(true).To(BeTrue(), "True should be true")
	})

	// Failing test for log analysis demo
	It("should fail on purpose", func() {
		fmt.Println("Running Intentional Failure Test")
		Expect(true).To(BeFalse(), "This test is designed to fail intentionally")
	})
})
