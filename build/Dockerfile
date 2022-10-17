FROM quay.io/app-sre/boilerplate:image-v2.3.2 AS builder

ENV PKG=/go/src/github.com/mrsantamaria/osde2e-example-test-harness/
WORKDIR ${PKG}

# compile test binary
COPY .. .
RUN make

FROM registry.access.redhat.com/ubi7/ubi-minimal:latest

COPY --from=builder /go/src/github.com/mrsantamaria/osde2e-example-test-harness/osde2e-example-test-harness.test osde2e-example-test-harness.test

ENTRYPOINT [ "/osde2e-example-test-harness.test" ]

