FROM brew.registry.redhat.io/rh-osbs/openshift-golang-builder:rhel_9_1.22 as builder
WORKDIR /go/src/github.com/openshift/osd-example-operator
COPY . .

FROM scratch

# Core bundle labels.
LABEL operators.operatorframework.io.bundle.mediatype.v1=registry+v1
LABEL operators.operatorframework.io.bundle.manifests.v1=manifests/
LABEL operators.operatorframework.io.bundle.metadata.v1=metadata/
LABEL operators.operatorframework.io.bundle.package.v1=osd-example-operator-bundle
LABEL operators.operatorframework.io.bundle.channels.v1=alpha
LABEL operators.operatorframework.io.metrics.builder=operator-sdk-v1.34.2
LABEL operators.operatorframework.io.metrics.mediatype.v1=metrics+v1
LABEL operators.operatorframework.io.metrics.project_layout=unknown

# Copy files to locations specified by labels.
COPY --from=builder /go/src/github.com/openshift/osd-example-operator/bundle/manifests /manifests/
COPY --from=builder /go/src/github.com/openshift/osd-example-operator/bundle/metadata /metadata/
