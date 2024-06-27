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
COPY bundle/manifests /manifests/
COPY bundle/metadata /metadata/

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
