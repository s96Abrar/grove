.PHONY: build check icon package release-preflight lint perf
build:
	bash scripts/build-app.sh
check:
	GROVE_RUN_GUI_CHECKS=1 bash scripts/check.sh
icon:
	swift scripts/render-icon.swift Resources/AppIcon.png
package:
	python3 scripts/release.py --mode local
release-preflight:
	python3 scripts/release.py --mode tagged --preflight-only

lint:
	bash scripts/lint-workflows.sh

perf:
	python3 scripts/perf.py
