VERSION := $(shell cat VERSION | tr -d '[:space:]')
DOCKER_REPO := hayamiz/kamosu
IMAGE := $(DOCKER_REPO):$(VERSION)
IMAGE_LATEST := $(DOCKER_REPO):latest
TEST_OUTPUT := test-output

.PHONY: help build build-nc test test-init smoke shell run-init clean release-check release push version

## help: Show this help message (default target)
help:
	@echo "kamosu v$(VERSION) — Development Targets"
	@echo ""
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /' | column -t -s ':'
	@echo ""

## build: Build Docker image
build:
	docker build --build-arg KB_TOOLKIT_VERSION=$(VERSION) -t $(IMAGE) -t $(IMAGE_LATEST) -t kamosu:latest .

## build-nc: Build Docker image (no cache)
build-nc:
	docker build --no-cache --build-arg KB_TOOLKIT_VERSION=$(VERSION) -t $(IMAGE) -t $(IMAGE_LATEST) -t kamosu:latest .

## test: Run all tests
test: build
	@bash tests/run_tests.sh

## test-init: Run kamosu-init scaffolding tests only
test-init: build
	@bash tests/test_kamosu_init.sh

## smoke: Build + init + verify (end-to-end smoke test)
smoke: build
	@bash tests/test_smoke.sh

## shell: Enter a bash shell in the kamosu container
shell: build
	docker run --rm -it -v $(PWD)/$(TEST_OUTPUT):/output kamosu:latest bash

## run-init: Run kamosu-init with test KB (output to test-output/)
run-init: build
	@mkdir -p $(TEST_OUTPUT)
	docker run --rm -v $(PWD)/$(TEST_OUTPUT):/output kamosu:latest kamosu-init --claude-oauth smoke-test

## clean: Remove test output and build artifacts
clean:
	@if [ -d "$(TEST_OUTPUT)" ]; then \
		docker run --rm -v $(PWD)/$(TEST_OUTPUT):/output kamosu:latest rm -rf /output/*; \
		rmdir $(TEST_OUTPUT) 2>/dev/null || true; \
	fi
	@echo "Cleaned."

## version: Show current version
version:
	@echo $(VERSION)

## release-check: Run pre-release checks
release-check:
	@echo "=== Release Check for v$(VERSION) ==="
	@# 1. CHANGELOG has version entry
	@grep -q '## \[$(VERSION)\]' CHANGELOG.md || \
		(echo "FAIL: CHANGELOG.md missing [$(VERSION)] entry" && exit 1)
	@# 2. CHANGELOG entry has date
	@grep '## \[$(VERSION)\] - [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' CHANGELOG.md > /dev/null || \
		(echo "FAIL: CHANGELOG.md [$(VERSION)] entry missing date" && exit 1)
	@# 3. Git tag does not exist yet
	@if git tag -l "v$(VERSION)" | grep -q .; then \
		echo "FAIL: git tag v$(VERSION) already exists"; exit 1; \
	fi
	@# 4. Working tree is clean
	@if ! git diff --quiet || ! git diff --cached --quiet; then \
		echo "FAIL: uncommitted changes exist"; exit 1; \
	fi
	@# 5. On main branch
	@BRANCH=$$(git branch --show-current); \
	if [ "$$BRANCH" != "main" ] && [ "$$BRANCH" != "master" ]; then \
		echo "FAIL: not on main/master branch (on $$BRANCH)"; exit 1; \
	fi
	@# 6. Check Migration Required section for MINOR/MAJOR bumps
	@echo "All checks passed for v$(VERSION)."

## release: Create release tag and push (with confirmation)
release: release-check
	@echo ""
	@echo "About to release v$(VERSION):"
	@echo "  - Create git tag v$(VERSION)"
	@echo "  - Push to origin"
	@echo ""
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || (echo "Aborted." && exit 1)
	git tag -a "v$(VERSION)" -m "Release v$(VERSION)"
	git push origin $$(git branch --show-current)
	git push origin "v$(VERSION)"
	@echo "Released v$(VERSION)."

## push: Push Docker image to registry (with confirmation)
push: build
	@echo "About to push $(IMAGE) and $(IMAGE_LATEST) to Docker Hub."
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || (echo "Aborted." && exit 1)
	docker push $(IMAGE)
	docker push $(IMAGE_LATEST)
	@echo "Pushed $(IMAGE) and $(IMAGE_LATEST)."
