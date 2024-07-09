#!/usr/bin/env bash

set -e

if ! command -v opm ; then
	curl -LO https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/opm-linux.tar.gz
	tar xzvf opm-linux.tar.gz
	PATH="${PATH}:."
fi

mkdir catalog/

bundle_image=quay.io/redhat-user-workloads/oeo-cicada-tenant/osd-example-operator/bundle@sha256:544c98263fc244edeae3755c7e8e4f92bfd61cc84f9a5e2e5a7de687858e3818

opm generate dockerfile catalog/ \
	-i registry.redhat.io/openshift4/ose-operator-registry:latest

opm index add \
	--bundles "${bundle_image}" \
	--generate

opm render \
	--output yaml \
	--migrate database/index.db > catalog/index.yaml

rm -rf database/ index.Dockerfile
