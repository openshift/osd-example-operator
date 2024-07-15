#!/usr/bin/env bash

set -xe

mkdir catalog/

operator_name=osd-example-operator
default_channel=stable
bundle_image=quay.io/redhat-user-workloads/oeo-cicada-tenant/osd-example-operator/bundle@sha256:570c3e3808236d003d0430f035f7c108200c7adc3927e49919aea830c6ed95d2

opm generate dockerfile catalog/ \
	--binary-image=registry.redhat.io/openshift4/ose-operator-registry:latest

opm init "${operator_name}" \
	--default-channel="${default_channel}" \
	--description=./README.md \
	--output=yaml > catalog/operator.yaml

opm render "${bundle_image}" --output=yaml >> catalog/operator.yaml

cat << EOF >> catalog/operator.yaml
---
schema: olm.channel
package: "${operator_name}"
name: "${default_channel}"
entries:
  - name: ${operator_name}.v${VERSION}
EOF

opm validate catalog
