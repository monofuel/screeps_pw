.DEFAULT_GOAL := build
NIM ?= nim
VERSION ?= 0.1.6
GAME_IMAGE ?=

.PHONY: deps engine build wasm-example test integration upload-integration viewer browser-test director-browser-test package certify check
deps:
	$(NIM) r tools/deps.nim
engine:
	$(NIM) r tools/engine.nim
build:
	$(NIM) r tools/build.nim
wasm-example:
	$(NIM) r tools/wasmExample.nim
check:
	$(NIM) check tools/match.nim
	$(NIM) js runtime/control.nim
	$(NIM) js runtime/launcher.nim
	$(NIM) check src/policyUpload.nim
test:
	$(NIM) r tests/test_rules.nim
	$(NIM) r tests/test_replays.nim
	$(NIM) r tests/test_replayDirector.nim
	$(NIM) r tests/test_worldFixture.nim
	$(NIM) js runtime/policyCheck.nim
	$(NIM) r tests/test_policies.nim
integration: build
	$(NIM) r tests/test_integration.nim
upload-integration: package
	$(NIM) r tests/test_uploadStaging.nim
viewer:
	$(NIM) r tools/viewer.nim
browser-test:
	$(NIM) r tools/browserCheck.nim "$(REPLAY)"
director-browser-test:
	$(NIM) r tools/browserCheck.nim "$(REPLAY)" --director
package: build
	$(NIM) r tools/package.nim $(VERSION) "$(GAME_IMAGE)"
certify:
	$(NIM) r tools/sdk.nim certify dist/coworld_manifest.json --timeout-seconds 300 --no-open-report
