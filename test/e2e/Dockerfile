# THIS FILE IS GENERATED BY BOILERPLATE. DO NOT EDIT.
FROM brew.registry.redhat.io/rh-osbs/openshift-golang-builder:rhel_8_1.23 as builder
WORKDIR /go/src/github.com/openshift/osd-example-operator/
COPY . .
RUN  CGO_ENABLED=0 GOFLAGS="-mod=mod" go test ./test/e2e -v -c --tags=osde2e -o /e2e.test

FROM registry.access.redhat.com/ubi8/ubi-minimal:latest
COPY --from=builder ./e2e.test e2e.test
ENTRYPOINT [ "/e2e.test" ]
