# osde2e-example-test-harness

This is an example test harness meant for testing the osde2e example operator addon. It does the following:

* Tests for the existence of the prowjobs.prow.k8s.io CRD. This should be present if the prow
  operator addon has been installed properly.
* Writes out a junit XML file with tests results to the /test-run-results directory as expected
  by the [https://github.com/openshift/osde2e](osde2e) test framework.
* Writes out an `addon-metadata.json` file which will also be consumed by the osde2e test framework.
