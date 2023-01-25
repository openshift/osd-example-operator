package e2e_test_harness_templates

import (
	"path/filepath"
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	_ "github.com/openshift/osde2e-example-test-harness/pkg/tests"
)

const (
	testResultsDirectory = "/test-run-results"
	jUnitOutputFilename  = "junit-example-addon.xml"
)

// Test entrypoint. osde2e runs this as a test suite on test pod.
func TestExampleTestHarness(t *testing.T) {
	RegisterFailHandler(Fail)

	suiteConfig, reporterConfig := GinkgoConfiguration()
	reporterConfig.JUnitReport = filepath.Join(testResultsDirectory, jUnitOutputFilename)
	RunSpecs(t, "Example E2E Test Harness", suiteConfig, reporterConfig)

}
