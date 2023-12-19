
<!-- TOC -->
- [Introduction](#introduction)
	- [What's in the Test Harness](#whats-in-the-test-harness)
	- [Locally Running Test Harness](#locally-running-test-harness)
      - [Using osde2e](#using-osde2e)
      - [Using ginkgo](#using-ginkgo)
	- [Tekton CI Job](#tekton-ci-job)
      - [Slack Notifications](#slack-notifications)
      - [Examining Test Results](#examining-test-results)
      - [Testing in More Environments](#testing-in-more-environments)
      - [Gating Deployments](#gating-deployments)
<!-- TOC -->

# Introduction

 
1. Why test harness? 
 
 Test harnesses are standalone ginkgo test images which hook easily into osde2e  framework.

2. Why osde2e  framework?

- Osde2e provides a customizable test environment complete with openshift clusters for customer behaviors to be simulated for an end to end test experience. 
- It offers enhanced ginkgo assertions as well as cloud apis which can be used, without the need to duplicate their implementation in each component needing e2e testing. 

This respository is an example of an operator test harness.  It is an example operator with a basic test assertion in the harness test suite.
 

## What's in the Test Harness

An empty scaffolding for test harness can be created in any operator under `/osde2e` by
- subscribing to boilerplate convention `openshift/golang-osd-operator-osde2e` in your `boilerplate/update.cfg`
- running `make boilerplate-update`, commit, and then `make e2e-harness-generate`


Test harness, created in `osde2e/` folder, consists of the following things
- `<operator-name_>test_harness_runner_test.go` : test runner which also provides  ginkgo configurations to tests
- `<operator-name_>test_harness_tests.go` : contains actual e2e test specs. This is where test coverage should be maintained. 
- `test-harness-template.yml` : dictates the job template run on tekton CI jobs in operator pipeline
- `Dockerfile` : builds docker image out of ginkgo test binary from the harness tests

 
## Locally Running Test Harness 

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
  ./osde2e test \
  --configs rosa,stage,sts,test-harness \
  --skip-must-gather \
  --skip-destroy-cluster \
  --skip-health-check 
  ```

## Using ginkgo
1. create stage rosa cluster
2. install ginkgo executable
3. get kubeadmin credentials from your cluster using `ocm get /api/clusters_mgmt/v1/clusters/$CLUSTER_ID/credentials | jq -r .kubeconfig > /<path-to>/kubeconfig`
4. Run harness using `OCM_ENVIRONMENT=stage KUBECONFIG=/<path-to>/kubeconfig  /<path-to>/bin/ginkgo  --tags=osde2e -v `
5. This will show test results, but also one execution error due to reporting configs. You can ignore this, or get rid of this, by temporarily removing the `suiteConfig` and `reporterConfig` arguments from `RunSpecs()` function in `osde2e/<operator-name_>test_harness_runner_test.go` file
 
## Tekton CI Job

To use test harness in your CI flow, it is set up as a saas based tekton job using [app-interface](https://gitlab.cee.redhat.com/service/app-interface) framework.

This job watches operator deployment success in stage environment, then runs the test job on the deployed operator version, with the same test image version. The turnaround time for results is less than 2 hours after a main branch update. 

Following files are relevant in configuring this job: 
 - Test job yaml in /data/services/osd-operators/cicd/saas/saas-<operator-name>/osde2e-focus-tests.yaml 
   - This file contains job specifications for e2e test job 
   - [Example](https://gitlab.cee.redhat.com/service/app-interface/-/blob/master/data/services/osd-operators/cicd/saas/saas-rbac-permissions-operator/osde2e-focus-test.yaml)
 - Operator saas file in /data/services/osd-operators/cicd/saas/saas-<operator-name>.yaml
   - This file configures operator deployment, and thus contains upstream trigger for e2e test job. Once operator is deployed to stage successfully, e2e job is triggered.
   - [Example](https://gitlab.cee.redhat.com/service/app-interface/-/blob/master/data/services/osd-operators/cicd/saas/saas-rbac-permissions-operator.yaml)
 - Job template file under operator repository`/osde2e/test-harness-template.yml`
   - This file contains openshift yaml spec for the job resource running osde2e in `e2e-testing` namespace in `hives02ue1`, once the tekton job is triggered, which in turns runs the test harness container in an ephemeral cluster, which uploads results to s3 after completion.
   - [Example](https://github.com/openshift/rbac-permissions-operator/blob/master/osde2e/test-harness-template.yml)

## Slack Notifications 
A a slack notification can be sent to the operator owner team on completion of the e2e test CI job.

To set it up, use [this example](https://gitlab.cee.redhat.com/service/app-interface/-/blob/master/data/services/osd-operators/cicd/saas/saas-managed-node-metadata-operator/osde2e-focus-test.yaml#L11)

OR add the following block to the `osde2e-focus-tests.yaml` in app-interface for your operator
```yaml
slack:
  workspace:
    $ref: /dependencies/slack/redhat-internal.yml
  channel: <slack team channel>
```

## Examining Test Results
1. Test results: To view test results, log in to the aws console of the aws account listed [in this vault](https://vault.devshift.net/ui/vault/secrets/osde2e/show/sdcicd_aws)
1. Go to [s3](https://s3.console.aws.amazon.com/s3/buckets/osde2e-logs?region=us-east-1&tab=objects), find the bucket named `osde2e_logs`, and locate your operator name with the timestamp closest to your job run. These will be deleted permanently after one month.
1. Main pod stdout: The Slack notification will contain links to your tekton job on app-sre cluster's tekton dashboard. You can review `osde2e` main pod logs here.

## Testing in More Environments
- Currently, this job runs only on hives02ue1 after operator is deployed on it
- If you wish to add the test to additional deployment, 
- Ensure the deployment step in saas file contains a unique promotion.publish event such as [this](https://gitlab.cee.redhat.com/service/app-interface/-/blob/master/data/services/osd-operators/cicd/saas/saas-rbac-permissions-operator.yaml#L59)
- Add another promotion step in your `osde2e-focus-tests.yaml` file for this new event similar to [this](https://gitlab.cee.redhat.com/service/app-interface/-/blob/master/data/services/osd-operators/cicd/saas/saas-rbac-permissions-operator/osde2e-focus-test.yaml#L55)

## Gating Deployments 
- To block deployment to an environment, e.g. stage, based on test job results from another environment, e.g. int, edit your saas-<operator-name>.yaml saas file, and add a block of `promotion.subscribe` config similar to [this](https://gitlab.cee.redhat.com/service/app-interface/-/blob/master/data/services/osd-operators/cicd/saas/saas-rbac-permissions-operator/osde2e-focus-test.yaml#L53-L58) within the deployment block for that environment, e.g. stage02 [here](https://gitlab.cee.redhat.com/service/app-interface/-/blob/master/data/services/osd-operators/cicd/saas/saas-rbac-permissions-operator.yaml#L51)
- The subscribe event name must match the [publish event name](https://gitlab.cee.redhat.com/service/app-interface/-/blob/master/data/services/osd-operators/cicd/saas/saas-rbac-permissions-operator/osde2e-focus-test.yaml#L58) for the test job, so that the deployment step can watch this event for success. 
