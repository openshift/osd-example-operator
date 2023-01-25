FROM registry.ci.openshift.org/openshift/release:golang-1.18 AS builder

ENV PKG=/go/src/github.com/openshift/osde2e-example-test-harness/
WORKDIR ${PKG}

# compile test binary
COPY . .

FROM registry.access.redhat.com/ubi7/ubi-minimal:latest

COPY ./osde2e/osde2e.test osde2e.test

ENTRYPOINT [ "/osde2e.test" ]