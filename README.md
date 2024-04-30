# osd-example-operator

This repository serves as a test bed for the SD-CICD team to build tooling and
support operators with minimal impact on other teams

## Complete SOP on operator test harness

https://github.com/openshift/ops-sop/blob/master/v4/howto/osde2e/operator-test-harnesses.md

## Locally Running Test Harness
- Run `make e2e-harness-build`  to make sure harness builds ok
- Deploy your new version of operator in a test cluster
- Ensure e2e test scenarios run green on a test cluster using one of the methods below

### Using ginkgo
1. create stage rosa cluster
2. install ginkgo executable
3. get kubeadmin credentials from your cluster using
```
ocm get /api/clusters_mgmt/v1/clusters/$CLUSTER_ID/credentials | jq -r .kubeconfig > /<path-to>/kubeconfig
```
4. Run harness using
```
OCM_ENVIRONMENT=stage KUBECONFIG=/<path-to>/kubeconfig  ./<path-to>/bin/ginkgo  --tags=osde2e -v 
```
5. This will show test results, but also one execution error due to reporting configs. You can ignore this, or get rid of this, by temporarily removing the `suiteConfig` and `reporterConfig` arguments from `RunSpecs()` function in `osde2e/<operator-name_>test_harness_runner_test.go` file


### Using osde2e

1. Publish a docker image for the test harness from operator repo using
   ```
   HARNESS_IMAGE_REPOSITORY=<your quay HARNESS_IMAGE_REPOSITORY>  HARNESS_IMAGE_NAME=<your quay HARNESS_IMAGE_NAME> make e2e-image-build-push
   ```
1. Create a stage rosa cluster
1. Clone osde2e: `git clone git@github.com:openshift/osde2e.git`
1. Build osde2e executable: `make build`
1. Run osde2e

  ```bash
  #!/usr/bin/env bash
  OCM_TOKEN="[OCM token here]" \ 
  CLUSTER_ID="[cluster id here]" \
  AWS_ACCESS_KEY_ID="[aws access key here]" \
  AWS_SECRET_ACCESS_KEY="[aws access secret here]" \
  TEST_HARNESSES="quay.io/$HARNESS_IMAGE_REPOSITORY/$HARNESS_IMAGE_NAME" \
#  Save results in specific local dir 
  REPORT_DIR="[path to local report directory]" \
#  OR in s3
  LOG_BUCKET="[name of the s3 bucket to upload log files to]" \
  ./out/osde2e test \
  --configs rosa,stage,sts,test-harness \
  --skip-must-gather \
  --skip-destroy-cluster \
  --skip-health-check 
