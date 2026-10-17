PYTHON ?= python3
VOICE_APP ?= VoiceInk

.PHONY: doctor doctor-json plan host test

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
