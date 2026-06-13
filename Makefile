# pkpass Quick Look — developer tasks
.PHONY: all project build test sample install uninstall clean help

PROJECT = PkpassQuickLook.xcodeproj
DESTINATION = platform=macOS
DERIVED = build

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

all: test build ## Run tests, then build

project: ## Regenerate the Xcode project from project.yml
	xcodegen generate

build: ## Build the app + extensions (Release, ad-hoc signed)
	xcodebuild build -project $(PROJECT) -scheme PkpassQuickLook \
	  -configuration Release -destination '$(DESTINATION)' \
	  -derivedDataPath $(DERIVED) CODE_SIGN_IDENTITY="-"

test: ## Run the unit tests
	xcodebuild test -project $(PROJECT) -scheme PkpassKit \
	  -destination '$(DESTINATION)' -derivedDataPath $(DERIVED) CODE_SIGNING_ALLOWED=NO

sample: ## Generate a sample pass into examples/
	swift scripts/make-sample-pass.swift

icon: ## Regenerate the app icon set
	swift scripts/make-app-icon.swift

gallery: ## Regenerate the demo-page pass-card gallery
	swiftc Sources/PkpassKit/*.swift scripts/make-gallery.swift -o /tmp/ql-gallery && /tmp/ql-gallery

install: ## Build, install to /Applications, and refresh Quick Look
	./scripts/install.sh

uninstall: ## Remove from /Applications and refresh Quick Look
	./scripts/uninstall.sh

clean: ## Remove build artifacts
	rm -rf build DerivedData
	xcodebuild clean -project $(PROJECT) -scheme PkpassQuickLook >/dev/null 2>&1 || true
