.PHONY: build run debug clean install

# Build a signed OpenFlow.app in build/
build:
	@bash Scripts/bundle.sh

# Build and launch it
run: build
	@pkill -x OpenFlow || true
	@open build/OpenFlow.app

# Faster iteration; permissions still stick because the signature is stable
debug:
	@CONFIG=debug bash Scripts/bundle.sh

# Copy to /Applications so launch-at-login and permissions behave normally
install: build
	@pkill -x OpenFlow || true
	@rm -rf /Applications/OpenFlow.app
	@cp -R build/OpenFlow.app /Applications/
	@echo "Zainstalowano w /Applications/OpenFlow.app"

# Tail the app's log output
logs:
	@log stream --predicate 'process == "OpenFlow"' --level info

clean:
	@rm -rf build .build
