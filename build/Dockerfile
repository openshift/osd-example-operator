FROM quay.io/redhat-services-prod/openshift/boilerplate:image-v7.4.0 AS builder
COPY go.mod /
COPY go.sum /
RUN go mod download
COPY . /osd-example-operator
WORKDIR /osd-example-operator
RUN make go-build

FROM registry.access.redhat.com/ubi8/ubi-minimal:8.10-1752564239
ENV OPERATOR=/usr/local/bin/osd-example-operator \
    USER_UID=1001 \
    USER_NAME=osd-example-operator
# install operator binary
COPY --from=builder /osd-example-operator/build/_output/bin/osd-example-operator ${OPERATOR}
COPY build/bin /usr/local/bin
RUN  /usr/local/bin/user_setup
ENTRYPOINT ["/usr/local/bin/entrypoint"]
USER ${USER_UID}
