.DEFAULT_GOAL := build
NIM ?= nim
VERSION ?= 0.1.4
GAME_IMAGE ?=

.PHONY: deps engine build test integration viewer browser-test director-browser-test package certify check
deps:
	$(NIM) r tools/deps.nim
engine:
	$(NIM) r tools/engine.nim
build:
	$(NIM) r tools/build.nim
check:
	$(NIM) check tools/match.nim
	$(NIM) js runtime/control.nim
	$(NIM) js runtime/launcher.nim
test:
	$(NIM) r tests/test_rules.nim
	$(NIM) r tests/test_replays.nim
	$(NIM) r tests/test_replayDirector.nim
	$(NIM) r tests/test_worldFixture.nim
integration: build
	$(NIM) r tests/test_integration.nim
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
