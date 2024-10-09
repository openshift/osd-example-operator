FROM quay.io/redhat-services-prod/boilerplate/image@sha256:5a74b6753803d0c88282f29e02a30f164f0b6ef839dfc47c4a4da890e0fc0a15 as builder

WORKDIR /workspace
# Copy the Go Modules manifests
COPY go.mod go.mod
COPY go.sum go.sum
# cache deps before building and copying source so that we don't need to re-download as much
# and so that source changes don't invalidate our downloaded layer
RUN go mod download

# Copy the go source
COPY main.go main.go
COPY controllers/ controllers/

# Copy the license
COPY LICENSE LICENSE

# Build
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GO111MODULE=on go build -mod=mod -a -o manager main.go

# Use distroless as minimal base image to package the manager binary
# Refer to https://github.com/GoogleContainerTools/distroless for more details
FROM registry.access.redhat.com/ubi8/ubi-minimal:8.10-1052.1724178568
WORKDIR /
RUN mkdir /licenses
COPY --from=builder /workspace/LICENSE /licenses/.
COPY --from=builder /workspace/manager .
USER nonroot:nonroot

ENTRYPOINT ["/manager"]
