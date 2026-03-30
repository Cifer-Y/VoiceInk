.PHONY: build run app install clean

build:
	swift build -c release

run:
	swift run

app: build
	bash build_app.sh

install: app
	cp -r VoiceInk.app /Applications/
	@echo "Installed to /Applications/VoiceInk.app"

clean:
	swift package clean
	rm -rf VoiceInk.app
