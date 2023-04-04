package exampleaddontestharness

import (
	"path/filepath"
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	"github.com/openshift/osde2e-example-test-harness/pkg/metadata"
	_ "github.com/openshift/osde2e-example-test-harness/pkg/tests"
)

const (
	testResultsDirectory    = "/test-run-results"
	jUnitOutputFilename     = "junit-example-addon.xml"
	testHarnessMetadataName = "test-harness-metadata.json"
)

func TestExampleAddonTestHarness(t *testing.T) {
	RegisterFailHandler(Fail)

	suiteConfig, reporterConfig := GinkgoConfiguration()
	reporterConfig.JUnitReport = filepath.Join(testResultsDirectory, jUnitOutputFilename)
	RunSpecs(t, "Example Addon Test Harness", suiteConfig, reporterConfig)

	err := metadata.Instance.WriteToJSON(filepath.Join(testResultsDirectory, testHarnessMetadataName))
	if err != nil {
		t.Errorf("error while writing metadata: %v", err)
	}
}
