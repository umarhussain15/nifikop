# Image URL to use all building/pushing image targets
SERVICE_NAME 			:= nifikop
DOCKER_REGISTRY_BASE 	?= orangeopensource
IMAGE_TAG 				?= $(shell git describe --tags --abbrev=0 --match '[0-9].*[0-9].*[0-9]' 2>/dev/null)
IMAGE_NAME 				?= $(SERVICE_NAME)

# Debug variables
TELEPRESENCE_REGISTRY ?= datawire

# Repository url for this project
# in gitlab CI_REGISTRY_IMAGE=repo/path/name:tag
ifdef CI_REGISTRY_IMAGE
	REPOSITORY := $(CI_REGISTRY_IMAGE)
else
	REPOSITORY := $(DOCKER_REGISTRY_BASE)/$(IMAGE_NAME)
endif

# Branch is used for the docker image version
ifdef CIRCLE_BRANCH
	#removing / for fork which lead to docker error
	BRANCH := $(subst /,-,$(CIRCLE_BRANCH))
else
	ifdef CIRCLE_TAG
		BRANCH := $(CIRCLE_TAG)
	else
		BRANCH=$(shell git rev-parse --abbrev-ref HEAD)
	endif
endif

# Operator version is managed in go file
# BaseVersion is for dev docker image tag
BASEVERSION := $(shell awk -F\" '/Version =/ { print $$2}' version/version.go)

ifdef CIRCLE_TAG
	VERSION := ${BRANCH}
else
	VERSION := $(BASEVERSION)-${BRANCH}
endif

HELM_VERSION    := $(shell cat helm/nifikop/Chart.yaml| grep version | awk -F"version: " '{print $$2}')
HELM_TARGET_DIR ?= docs/helm

#si branche master, on pousse le tag latest
ifeq ($(CIRCLE_BRANCH),master)
	PUSHLATEST := true
endif

# Shell to use for running scripts
SHELL := $(shell which bash)

# Get docker path or an empty string
DOCKER := $(shell command -v docker)

# Get the main unix group for the user running make (to be used by docker-compose later)
GID := $(shell id -g)

# Get the unix user id for the user running make (to be used by docker-compose later)
UID := $(shell id -u)

# Commit hash from git
COMMIT=$(shell git rev-parse HEAD)

# CMDs
UNIT_TEST_CMD := KUBERNETES_CONFIG=`pwd`/config/test-kube-config.yaml POD_NAME=test go test --cover --coverprofile=coverage.out `go list ./... | grep -v e2e` > test-report.out
UNIT_TEST_CMD_WITH_VENDOR := KUBERNETES_CONFIG=`pwd`/config/test-kube-config.yaml POD_NAME=test go test -mod=vendor --cover --coverprofile=coverage.out `go list -mod=vendor ./... | grep -v e2e` > test-report.out
UNIT_TEST_COVERAGE := go tool cover -html=coverage.out -o coverage.html
GO_GENERATE_CMD := go generate `go list ./... | grep -v /vendor/`
GO_LINT_CMD := golint `go list ./... | grep -v /vendor/`

# environment dirs
DEV_DIR := docker/circleci
APP_DIR := build/Dockerfile

OPERATOR_SDK_VERSION=v0.15.0
# workdir
WORKDIR := /go/nifikop

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
	GOOS = linux
endif
ifeq ($(UNAME_S),Darwin)
	GOOS = darwin
endif

# Some other useful make file for interacting with kubernetes
include kube.mk

# The default action of this Makefile is to build the development docker image
default: build

.DEFAULT_GOAL := help
help:
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)|(^##)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}{printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}' | sed -e 's/\[32m##/[33m/'

get-baseversion:
	@echo $(BASEVERSION)

get-version:
	@echo $(VERSION)

clean:
	@rm -rf $(OUT_BIN) || true
	@rm -f apis/nificluster/v1alpha1/zz_generated.deepcopy.go || true

helm-package:
	@echo Packaging $(HELM_VERSION)
	helm package helm/nifikop
	mv nifikop-$(HELM_VERSION).tgz $(HELM_TARGET_DIR)
	helm repo index $(HELM_TARGET_DIR)/

.PHONY: generate
generate:
	echo "Generate zzz-deepcopy objects"
	operator-sdk version
	operator-sdk generate k8s
	operator-sdk generate openapi

# Build nifikop executable file in local go env
.PHONY: build
build:
	echo "Generate zzz-deepcopy objects"
	operator-sdk version
	operator-sdk generate k8s
	operator-sdk generate openapi
	echo "Build Nifi Operator"
	operator-sdk build $(REPOSITORY):$(VERSION) --image-build-args "--build-arg https_proxy=$$https_proxy --build-arg http_proxy=$$http_proxy"
ifdef PUSHLATEST
	docker tag $(REPOSITORY):$(VERSION) $(REPOSITORY):latest
endif

debug-port-forward:
	kubectl port-forward `kubectl get pod -l app=nifikop -o jsonpath="{.items[0].metadata.name}"` 40000:40000

debug-pod-logs:
	kubectl logs -f `kubectl get pod -l app=nifikop -o jsonpath="{.items[0].metadata.name}"`

define debug_telepresence
	export TELEPRESENCE_REGISTRY=$(TELEPRESENCE_REGISTRY) ; \
	echo "execute : cat nifi-operator.env" ; \
	sudo mkdir -p /var/run/secrets/kubernetes.io ; \
	tdep=$(shell kubectl get deployment -l app=nifikop -o jsonpath='{.items[0].metadata.name}') ; \
  	echo kubectl get deployment -l app=nifikop -o jsonpath='{.items[0].metadata.name}' ; \
	echo telepresence --swap-deployment $$tdep --mount=/tmp/known --env-file nifi-operator.env $1 $2 ; \
 	telepresence --swap-deployment $$tdep --mount=/tmp/known --env-file nifi-operator.env $1 $2
endef


debug-telepresence:
	$(call debug_telepresence)

debug-telepresence-with-alias:
	$(call debug_telepresence,--also-proxy,10.40.0.0/16)

# Run the development environment (in local go env) in the background using local ~/.kube/config
run:
	export POD_NAME=nifikop; \
	operator-sdk up local

push:
	docker push $(REPOSITORY):$(VERSION)
ifdef PUSHLATEST
	docker push $(REPOSITORY):latest
endif

tag:
	git tag $(VERSION)

publish:
	@COMMIT_VERSION="$$(git rev-list -n 1 $(VERSION))"; \
	docker tag $(REPOSITORY):"$$COMMIT_VERSION" $(REPOSITORY):$(VERSION)
	docker push $(REPOSITORY):$(VERSION)
ifdef PUSHLATEST
	docker push $(REPOSITORY):latest
endif

release: tag image publish

# golint is not fully supported by modules yet - https://github.com/golang/lint/issues/409
go-lint:
	$(GO_LINT_CMD)

# Test if the dependencies we need to run this Makefile are installed
deps-development:
ifndef DOCKER
	@echo "Docker is not available. Please install docker"
	@exit 1
endif

#Generate dep for graph
UNAME := $(shell uname -s)

dep-graph:
ifeq ($(UNAME), Darwin)
	dep status -dot | dot -T png | open -f -a /Applications/Preview.app
endif
ifeq ($(UNAME), Linux)
	dep status -dot | dot -T png | display
endif