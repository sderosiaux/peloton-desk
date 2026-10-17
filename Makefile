PYTHON ?= python3
VOICE_APP ?= VoiceInk

.PHONY: doctor doctor-json plan host test app-build app-install app-doctor app-test asr-build license-check

asr-build:
	$(PYTHON) tools/build.py parakeet

license-check:
	.venv/bin/python tools/audit_licenses.py

app-build:
	npm run build
	$(PYTHON) tools/build.py mac
	$(PYTHON) tools/build.py android

app-install:
	$(PYTHON) tools/app.py install --serial "$(SERIAL)"

app-doctor:
	$(PYTHON) tools/app.py doctor

app-test: test
	npm test
	.venv/bin/python -m unittest discover -s macos/tests -q
	".local/Peloton Desk Mac.app/Contents/MacOS/PelotonDesk" --self-test

doctor:
	@$(PYTHON) tools/desk.py doctor --voice-app "$(VOICE_APP)"

doctor-json:
	@$(PYTHON) tools/desk.py doctor --voice-app "$(VOICE_APP)" --json

plan:
	@$(PYTHON) tools/desk.py launch-host --voice-app "$(VOICE_APP)" --dry-run

host:
	@$(PYTHON) tools/desk.py launch-host --voice-app "$(VOICE_APP)"

test:
	@$(PYTHON) -m unittest discover -s tests -q
