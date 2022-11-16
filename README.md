 <!-- TOC -->
* [osde2e-example-test-harness](#osde2e-example-test-harness)
  * [Designing e2e Tests](#designing-e2e-tests)
  * [The Structure of an Addon Test](#the-structure-of-an-addon-test)
  * [Locally Running This Example](#locally-running-this-example)
  * [Locally Running Your Test Harness](#locally-running-your-test-harness)
  * [Configuring OSDe2e](#configuring-osde2e)
    * [Example Periodic Prow Job Config](#example-periodic-prow-job-config)
    * [Parameters](#parameters)
    * [More on Secrets](#more-on-secrets)
        * [Passthrough Keys](#passthrough-keys)
  * [SKUs and Quota](#skus-and-quota)
    * [Addon Cleanup](#addon-cleanup)
    * [Slack Notifications](#slack-notifications)
  * [Querying results from Datahub](#querying-results-from-datahub)
<!-- TOC -->
# osde2e-example-test-harness

This respository is an example of a test harness. 
Test harnesses are standalone test repositories executed by osde2e framework in prow jobs. 
This example uses the Reference Addon as an example and demonstrates basic test assertions. 
It does the following:

* Contains source for example test-harness image published in: quay.io/rmundhe_oc/osde2e-example-test-harness
* Uses *Reference Addon* as example
* Asserts the existence of the reference-addon CRD i.e., *referenceaddons.reference.addons.managed.openshift.io*. This should be present if the *reference-addon* has been installed properly.
* When `osde2e` executes this harness, it writes out a junit XML file with tests results to the `/test-run-results` directory as expected
  by the [osde2e](https://github.com/openshift/osde2e)  test framework.
* And also writes an `addon-metadata.json` file which will also be consumed by the osde2e test framework.

You may use this exampe to create your own addon test harness.

> The addons integration (e2e) tests are not meant to replace any existing QE.
 This document is not a reference for complete onboarding procedure for addons to OSD. Full process of onboarding addons is outlined in the documentation [here](https://gitlab.cee.redhat.com/service/managed-tenants/-/tree/master).
 
## Designing e2e Tests
We recommend the following basic principles in designing your e2e tests:
 - Map existing functionality to e2e test cases
 - Map any bugs found into e2e test cases 
 - Update e2e test cases as addon functionality is changed or added 
 - Ensure the assertions and logs output by tests reflect 
   - the execution paths and 
   - potential causes of failures  

## The Structure of an Addon Test

How an add-on is tested can vary between groups and projects. In light of this, we've tried to create a very flexible and unopinionated framework for your testing. Your test harness should take the form of an OCI (docker) container that does the following:

*   Assume it is executing in a pod within an OpenShift cluster.
*   Assume the pod will inherit `cluster-admin` rights.
*	Block until your addon is ready to be tested (we will launch your container after requesting installation of the addon, but we can't control when the addon is finished installing).
*   Output a valid `junit.xml` file to the `/test-run-results` directory before the container exits.
*   Output metadata to `addon-metadata.json` in the `/test-run-results` directory.


## Locally Running This Example 

1. Create a stage rosa cluster
2. Clone osde2e: `git clone git@github.com:openshift/osde2e.git`
3. Build osde2e executable: `make build`
4. Run osde2e addon example suite

  ```bash
  #!/usr/bin/env bash
  OCM_TOKEN="[OCM token here]" \ 
  CLUSTER_ID="[cluster id here]" \
  ADDON_IDS="reference-addon" \ 
  ADDON_TEST_HARNESSES="quay.io/rmundhe_oc/osde2e-example-test-harness" \
  REPORT_DIR="[path to report directory]" \
  ROSA_ENV=stage \
  ./osde2e test \
  --configs rosa,stage,addon-suite \
  --must-gather false \
  --destroy-cluster false \
  --skip-health-check true
  ```
 
  **Arguments:** 
  - The `--configs` arg here maps to `$CONFIGS` environment var in the prow config, see description in [parameters](#parameters) section. 
  - `--destroy-cluster`, `--skip-health-check` and `--must-gather` help shorten the time consumed by the test to run locally. 

  **Environment variables:**
  - See [parameters](#parameters) section for description of environment variables used. 

Once the execution is complete, you can view the report in the defined `REPORT_DIR` directory.

After the Test Harness has been validated to work as intended locally, this flow can be performed in a CI pipeline to test agaisnt OSD releases as described below.

## Locally Running Your Test Harness
1. `ADDON_TEST_HARNESSES` image: 
   Build and push latest docker image i.e.
    ```bash
    sudo docker build . -t quay.io/<-- your test harness image-->
    sudo docker push quay.io/<--your test harness image-->
    ``` 
   Use this test image name as the `ADDON_TEST_HARNESSES` in step 5 below.
2. Follow the subsequent steps in the [example above](#locally-running-this-example). Remember to change `ADDON_TEST_HARNESSES` as well as `ADDON_IDS` to your addon. 
 
## Configuring OSDe2e

1. Write addon test harness by referring to this harness as an example.
2. Push the docker image to a quay repo.
3. Create a prow job using following example
4. Open a PR against the [openshift/release](https://github.com/openshift/release) repo.
 
### Example Periodic Prow Job Config
Defined in release repo: https://github.com/openshift/release/blob/master/ci-operator/jobs/openshift/osde2e/openshift-osde2e-main-periodics.yaml#L158 

Comments denote brief instructions. Do not update keys with no comments. For your job, do not copy from here, use the git version linked above instead. `ci-operator` does not like comments in yamls. 
```yaml
- agent: kubernetes
  cluster: build05
  cron: 0 14 * * 0 // runs once a week. update as needed. 
  decorate: true
  extra_refs:
    - base_ref: main
      org: openshift
      repo: osde2e
  labels:
    pj-rehearse.openshift.io/can-be-rehearsed: "false"
  name: osde2e-rosa-stage-example-addon  // update to your job in the format: osde2e-<provider>-<environement>-<addon_name>-addon
  spec:
    containers:
      - args:
          - test
          - --secret-locations
          - $(SECRET_LOCATIONS)
          - --configs
          - $(CONFIGS)
        command:
          - /osde2e
        env:
          - name: ADDON_IDS
            value: reference-addon // update to your addons
          - name: ADDON_TEST_HARNESSES
            value: quay.io/rmundhe_oc/osde2e-example-test-harness // update to your test harness image
          - name: CHANNEL
            value: stable
          - name: CONFIGS
            value: rosa,stage,addon-suite // update to your provider, environment, leave the suite config as is
          - name: ROSA_AWS_REGION
            value: random // update or remove
          - name: ROSA_ENV
            value: stage // update or remove
          - name: SECRET_LOCATIONS // update 
            value: /usr/local/osde2e-common,/usr/local/osde2e-credentials,/usr/local/osde2e-rosa-stage,/usr/local/example-addon-secret
        image: quay.io/app-sre/osde2e
        imagePullPolicy: Always
        name: ""
        resources:
          requests:
            cpu: 10m
        volumeMounts: // update as needed
          - mountPath: /usr/local/example-addon-secret // passthrough secret mount
            name: example-addon-secret
            readOnly: true
          - mountPath: /usr/local/osde2e-common  // Other osde2e credentials e.g. database, slack etc
            name: osde2e-common
            readOnly: true
          - mountPath: /usr/local/osde2e-credentials // OCM osde2e credentials
            name: osde2e-credentials
            readOnly: true
          - mountPath: /usr/local/osde2e-rosa-stage // rosa/aws stage osde2e credentials
            name: osde2e-rosa-stage
            readOnly: true
    serviceAccountName: ci-operator
    volumes: // update as needed
      - name: example-addon-secret   // passthrough secret volume
        secret:
          secretName: example-addon-secret
      - name: osde2e-common
        secret:
          secretName: osde2e-common
      - name: osde2e-credentials
        secret:
          secretName: osde2e-credentials
      - name: osde2e-rosa-stage
        secret:
          secretName: osde2e-rosa-stage
```

To adapt this to your job, you would redefine the values denoted with comments.


### Parameters ###

The following can be passed to `osde2e` executable as environment variables.


* `ADDON_TEST_USER`: The in-cluster user that the test harness containers will run as. Allows for a single wildcard (`%s`) which will automatically be evaluated as the namespace for the test harness.
* `ADDON_IDS`: Comma-delimited list of addons to install. e.g.
  ```yaml
      - name: ADDON_IDS
        value: managed-api-service
  ```
* `ADDON_TEST_HARNESSES`: Comma delimited list of docker images to run within the test namespace.
* `ADDON_PARAMETERS` allows you to pass parameters to your addon. The format is a two-level JSON object. The outer object's keys are the IDs of addons, and the inner objects are key-value pairs that will be passed to the associated addon. e.g.
  ```yaml
    - name: ADDON_PARAMETERS
      value: '{
       "managed-api-service":{
         "addon-managed-api-service": "1",
         "addon-resource-required":"true", 
         "cidr-range": "10.1.0.0/26"}
       }'
  ```
* ROSA variables
  * `ROSA_AWS_REGION`: (we recommend setting this to `random`)
  * `ROSA_ENV`:  `integration`, `stage`, or `production`
* `CHANNEL` lets you specify the Cincinnati channel for version selection. Valid options include `nightly`, `candidate`, `fast`, and `stable`. By default, this is set to `candidate`. It is best practice to have several pipelines.  One that tests as far left as you can (e.g. nightlies) and one that tests candidate, fast or stable.  The idea behind this is that your left-most test pipeline will give you early warning of things that may break in the future, giving you time to react to failed test notifications and fix things.
* `CONFIG`: Select environment, cloud provider and test suite. We have
  * 3 test environments: integration (int), staging (stage), and production (prod).
  * 3 providers: `rosa`, `gcp`, `aro`.  Each environment and each provider requires a separate prow job configuration.
  * Test suite for your addon tests should be `addon-suite`
    The `CONFIGS` variable loads the config files defined in [osde2e](https://github.com/openshift/osde2e/tree/main/configs). The *test harness example* runs on `rosa` `stage` environment and executes `addon-suite`. If you want your job to run in a different environment, such as `int` or `prod`, or a different cloud provider, such as `gcp` or `aro`, you need to
    * (A) change the job `name` key to include the proper environment and provider *and*
    * (B) redefine the `CONFIGS` environment variable by replacing `rosa` and `stage` with the name of the appropriate provider and environment for your prow job.


### More on Secrets

You'll need to provide some additional details about your AWS account in a secret. In particular, you'll need to provide these values in your credentials secret:

```
aws-account
aws-access-key
aws-secret-access-key
```

And the following optional key
```
aws-region
```
To set up your vault secrets, if you are not a part of the public GitHub Organization `OpenShift`, join it by following [these instructions](https://source.redhat.com/groups/public/atomicopenshift/atomicopenshift_wiki/setting_up_your_accounts_openshift).
Follow the documentation [here](https://docs.ci.openshift.org/docs/how-tos/adding-a-new-secret-to-ci/) to create these secrets.

##### Passthrough Keys  

You may need to provide any additional (a.k.a. passthrough) keys. Follow these steps to pass them:

1. Create the secret in vault, just as the secrets above, 
2. Change the target namespace of the keys you have created to the following:

```
secretsync/target-namespace: "osde2e-ci-secrets" # This is the namespace where the `ci-secrets` secret is created for all osde2e ci jobs
```

To load this key to your ci pipeline's cluster, you'll need to mount them to your test job. Use the example of `example-addon-secret` in the prow config example above.

To consume any of these passthrough keys loaded into the cluster, you may access them using

`oc get secret ci-secrets -n osde2e-ci-secrets`

Once loaded, the key will be listed as one of the key-value pairs contained in this secret and the value will be base64 encoded version of the one you specify in vault.

> The pipeline loads the secrets `osde2e-common` and `osde2e-credentials`, followed by the ones you supply. This allows your credentials to override any duplicate credentials supplied in our config.

## SKUs and Quota

In order to provision OSD and install your addon, our OCM token will need to have a quota of OSD clusters and installations of your addon available. In order to allocate quota for your addon, it must be assigned a SKU. You can request a SKU [by following these instructions](https://gitlab.cee.redhat.com/service/managed-tenants/-/tree/master).

Once you have a SKU, you'll need to also allocate quota to test within [`app-interface`](https://gitlab.cee.redhat.com/service/app-interface/#manage-openshift-resourcequotas-via-app-interface-openshiftquota-1yml). Quota is allocated independently in each of `int`, `stage`, and `prod` (different instances of OCM), so you'll need to allocate quota three times.

[Here](https://gitlab.cee.redhat.com/service/ocm-resources/-/blob/master/data/uhc-production/orgs/13215750.yaml#L13) is an example of SD-CICD's quota for production.

You need to open an MR to update the `SDCICD` org's quota so that it can provision your addon (as well as bumping the number of CCS clusters by 2 or so). You'll need to modify the following three files:

- [Our production quota](https://gitlab.cee.redhat.com/service/ocm-resources/-/blob/master/data/uhc-production/orgs/13215750.yaml)
- [Our stage quota](https://gitlab.cee.redhat.com/service/ocm-resources/-/blob/master/data/uhc-stage/orgs/13215750.yaml)
- [Our integration quota](https://gitlab.cee.redhat.com/service/ocm-resources/-/blob/master/data/uhc-integration/orgs/13215750.yaml)

Please bump the quota for SKU `MW00530` by 2 so that we can provision additional CCS clusters for you!


### Addon Cleanup

If your addon test creates or affects anything outside the OSD cluster lifecycle, a separate cleanup action is required. If `ADDON_RUN_CLEANUP` is set to `true`, OSDe2e will run your test harness container a **second time** passing the argument `cleanup` to the container (as the first command line argument).

There may be a case where a separate cleanup container/harness is required. That may be configured using the `ADDON_CLEANUP_HARNESSES` config option. It is formatted in the same way as `ADDON_TEST_HARNESSES`. This however, may cause some confusion as to what is run when:

`ADDON_RUN_CLEANUP` is true, and `ADDON_CLEANUP_HARNESSES` is not set, OSDe2e will only run `ADDON_TEST_HARNESSES` again, passing the `cleanup` argument.

`ADDON_RUN_CLEANUP` is true, and `ADDON_CLEANUP_HARNESSES` is set, OSDe2e will only run the `ADDON_CLEANUP_HARNESSES`, passing no arguments.

> *NOTE*: Your OSD clusters will automatically back themselves up to S3 in your AWS account. You can find these backups by running `aws s3 ls --profile osd`. You should probably clean them up as part of the cleanup phase of your build.

### Slack Notifications

If you want to be notified of the results of your builds in slack, you can take advantage of [this feature](https://docs.ci.openshift.org/docs/how-tos/notification/). [Here](https://github.com/openshift/release/pull/16674/files#diff-d214756a87b37f0ad838abce8ddfa8993c7cd6a7614fc15384f5f3e4307f079aR1983) is an example PR of someone configuring slack alerts for an Addon.



## Querying results from Datahub

Once your job has been running in prow, you will be able to programmatically query Thanos/Prometheus for job results. All OSDe2e data points stored within Thanos/Prometheus are prefixed with `cicd_`. Currently there are three primary metrics stored:

```
cicd_event{environment="int",event="InstallSuccessful",install_version="openshift-v4.2.0-0.nightly-2020-01-15-224532",job="periodic-ci-openshift-osde2e-master-e2e-int-4.2-4.2",monitor="datahub",upgrade_version="openshift-v4.2.0-0.nightly-2020-01-15-231532"}

cicd_jUnitResult{environment="int",install_version="openshift-v4.2.0-0.nightly-2020-01-15-224532",job="periodic-ci-openshift-osde2e-master-e2e-int-4.2-4.2",monitor="datahub",phase="install",result="failed",suite="OSD e2e suite",testname="[OSD] Managed Velero Operator deployment should have all desired replicas ready",upgrade_version="openshift-v4.2.0-0.nightly-2020-01-15-231532"}

cicd_metadata{cluster_id="1a2bc3",environment="int",install_version="openshift-v4.2.0-0.nightly-2020-01-15-224532",job="periodic-ci-openshift-osde2e-master-e2e-int-4.2-4.2",job_id="123",metadata_name="time-to-cluster-ready",monitor="datahub",phase="",upgrade_version="openshift-v4.2.0-0.nightly-2020-01-15-231532"}

cicd_addon_metadata{cluster_id="1a2bc3",environment="int",install_version="openshift-v4.2.0-0.nightly-2020-01-15-224532",job="periodic-ci-openshift-osde2e-master-e2e-int-4.2-4.2",job_id="123",metadata_name="time-to-cluster-ready",monitor="datahub",phase="",upgrade_version="openshift-v4.2.0-0.nightly-2020-01-15-231532"}
```

In addition to programmatically gating your addon releases, you can also use the [Grafana instance] hosted by DataHub to build out a dashboard and alerting to monitor the health of the addon as versions change.

 
 
 
[Managing Organization Quota]:https://gitlab.cee.redhat.com/service/ocm-resources/blob/master/docs/quota.md
[https://cloud.redhat.com/openshift/token]:https://cloud.redhat.com/openshift/token
[Grafana instance]:https://grafana.datahub.redhat.com/
