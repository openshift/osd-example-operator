#!/usr/bin/env bash

if ! command -v operator-sdk ; then
	curl -L https://github.com/operator-framework/operator-sdk/releases/latest/download/operator-sdk_linux_amd64 -o operator-sdk
	chmod +x ./operator-sdk
	PATH="${PATH}:."
fi

operator-sdk generate bundle --overwrite --version "${VERSION}" --input-dir deploy/ --package "${OPERATOR_NAME}-bundle"
