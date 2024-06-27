FROM brew.registry.redhat.io/rh-osbs/openshift-golang-builder:rhel_9_1.22 as builder
WORKDIR /go/src/github.com/openshift/osd-example-operator
COPY . .

ARG OPERATOR_IMAGE_BUILD=quay.io/redhat-user-workloads/oeo-cicada-tenant/osd-example-operator/osd-example-operator-build:84e8a4412ec6850e43b630bd70d8812b848e62d1
RUN make update-bundle

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

LABEL name="osd-example-operator" \
     distribution-scope="public" \
     release="0.0.1" \
     version="0.0.1" \
     url="https://github.com/openshift/osd-example-operator" \
     vendor="Red Hat, Inc." \
     description="Example operator used for testing in Service Delivery" \
     summary="sample operator configured similarly to production SD operators used for testing" \
     com.redhat.component="osd-example-operator" \
     io.k8s.description="osd-example-operator" \
     io.k8s.display-name="osd-example-operator" \
     io.openshift.tags="data,images"
