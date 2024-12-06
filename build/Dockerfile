FROM quay.io/redhat-services-prod/openshift/boilerplate:image-v6.0.1 AS builder

WORKDIR /workspace
COPY go.mod go.mod
COPY go.sum go.sum
RUN go mod download

COPY . .
RUN make go-build

FROM registry.access.redhat.com/ubi8/ubi-minimal:8.10-1130
ENV OPERATOR=/usr/local/bin/must-gather-operator \
    USER_UID=1001 \
    USER_NAME=osd-example-operator

COPY --from=builder /workspace/build/_output/bin/* /usr/local/bin/

COPY build/bin /usr/local/bin
RUN /usr/local/bin/user_setup

ENTRYPOINT ["/usr/local/bin/entrypoint"]

USER ${USER_UID}

LABEL io.openshift.managed.name="osd-example-operator" \
      io.openshift.managed.description="OSD Example Operator"
