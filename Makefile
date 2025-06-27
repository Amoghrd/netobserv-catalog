
IMAGE ?= quay.io/$(USER)/network-observability-operator-catalog:latest
BUILD_STREAM ?= y-stream
OCI_BIN_PATH := $(shell which docker 2>/dev/null || which podman)
OCI_BIN ?= $(shell basename ${OCI_BIN_PATH})

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Tools

.PHONY: prereqs
prereqs: ## Prerequisites: installs opm and yq
	go install github.com/operator-framework/operator-registry/cmd/opm@v1.51.0
	go install github.com/mikefarah/yq/v4@v4.35.2

##@ Updating the catalogs

.PHONY: generate
generate: prereqs ## Regenerate all catalogs from scratch
	rm -f ./auto-generated/catalog/*
	rm -f ./auto-generated/legacy-catalog/*
	for i in $(shell ls ./templates/ | grep yaml); do \
		opm alpha render-template basic --migrate-level=bundle-object-to-csv-metadata  -o yaml ./templates/$$i > ./auto-generated/catalog/$$i; \
		opm alpha render-template basic -o yaml ./templates/$$i > ./auto-generated/legacy-catalog/$$i; \
		sed -i -e 's#quay.io/redhat-user-workloads/ocp-network-observab-tenant/network-observability-operator-bundle-zstream#registry.redhat.io/network-observability/network-observability-operator-bundle#g' ./auto-generated/catalog/$$i; \
		sed -i -e 's#quay.io/redhat-user-workloads/ocp-network-observab-tenant/network-observability-operator-bundle-zstream#registry.redhat.io/network-observability/network-observability-operator-bundle#g' ./auto-generated/legacy-catalog/$$i; \
		sed -i -e 's#quay.io/redhat-user-workloads/ocp-network-observab-tenant/network-observability-operator-bundle-ystream#registry.redhat.io/network-observability/network-observability-operator-bundle#g' ./auto-generated/catalog/$$i; \
		sed -i -e 's#quay.io/redhat-user-workloads/ocp-network-observab-tenant/network-observability-operator-bundle-ystream#registry.redhat.io/network-observability/network-observability-operator-bundle#g' ./auto-generated/legacy-catalog/$$i; \
	done

.PHONY: next-ystream
next-ystream: ## Set current release to ystream next
	cp ./templates/y-stream.Dockerfile-args ./templates/next-release.Dockerfile-args
	cp ./templates/y-stream.yaml ./templates/released.yaml
	cp ./auto-generated/catalog/y-stream.yaml ./auto-generated/catalog/released.yaml
	cp ./auto-generated/legacy-catalog/y-stream.yaml ./auto-generated/legacy-catalog/released.yaml
	sed -i 's/zstream/ystream/' .tekton/images-mirror-set.yaml

.PHONY: next-zstream
next-zstream: ## Set current release to zstream next
	cp ./templates/z-stream.Dockerfile-args ./templates/next-release.Dockerfile-args
	cp ./templates/z-stream.yaml ./templates/released.yaml
	cp ./auto-generated/catalog/z-stream.yaml ./auto-generated/catalog/released.yaml
	cp ./auto-generated/legacy-catalog/z-stream.yaml ./auto-generated/legacy-catalog/released.yaml
	sed -i 's/ystream/zstream/' .tekton/images-mirror-set.yaml

##@ Testing

.PHONY: build-image
build-image: ## Build the catalog image
	$(OCI_BIN) build --build-arg INDEX_FILE="./auto-generated/catalog/$(BUILD_STREAM).yaml" -t $(IMAGE) -f upstream.Dockerfile .

.PHONY: push-image
push-image: ## Push the catalog image to a remote registry
	$(OCI_BIN) push ${IMAGE}

.PHONY: deploy
deploy: ## Deploy the catalog image on a cluster
	yq '.spec.image="$(IMAGE)"' ./catalog-source.yaml | kubectl apply -f -

.PHONY: undeploy
undeploy: ## Undeploy the catalog image from a cluster
	kubectl delete -f ./catalog-source.yaml
