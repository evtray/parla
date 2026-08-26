DEVDIR := $(shell xcode-select -p)
XFRAMEWORKS := $(DEVDIR)/Library/Developer/Frameworks
XLIBS := $(DEVDIR)/Library/Developer/usr/lib
DIST := dist
XCBUILD := .build/xcode

# Solo Command Line Tools necesita ayuda para encontrar swift-testing.
TESTFLAGS := $(if $(wildcard $(XLIBS)/lib_TestingInterop.dylib), \
  -Xswiftc -F -Xswiftc $(XFRAMEWORKS) \
  -Xlinker -F -Xlinker $(XFRAMEWORKS) \
  -Xlinker -rpath -Xlinker $(XFRAMEWORKS) \
  -Xlinker -rpath -Xlinker $(XLIBS),)

.PHONY: test generate build run install release open clean

test:
	cd Core && swift test $(TESTFLAGS)

generate:
	xcodegen generate

# Siempre regenera: si añades un archivo y no lo haces, Xcode no lo ve.
build: generate
	xcodebuild -project Parla.xcodeproj -scheme Parla -configuration Debug build

run: build
	@pkill -f 'Parla.app/Contents/MacOS/Parla' 2>/dev/null || true
	@open "$$(xcodebuild -project Parla.xcodeproj -scheme Parla -configuration Debug \
	  -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $$2}')/Parla.app"

# Deja la app en /Applications para poder abrirla desde Spotlight.
install: build
	@pkill -f 'Parla.app/Contents/MacOS/Parla' 2>/dev/null || true
	@rm -rf /Applications/Parla.app
	@cp -R "$$(xcodebuild -project Parla.xcodeproj -scheme Parla -configuration Debug \
	  -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $$2}')/Parla.app" \
	  /Applications/
	@echo "Parla instalada en /Applications. Ábrela con Spotlight (⌘Espacio → Parla)."

# Compilación Release firmada ad-hoc, empaquetada en dist/.
# Sin certificado Developer ID no se puede notarizar: en OTRO Mac, Gatekeeper
# la bloqueará y habrá que abrirla con clic derecho > Abrir la primera vez.
release: generate
	rm -rf $(DIST) $(XCBUILD)
	xcodebuild -project Parla.xcodeproj -scheme Parla -configuration Release \
	  -derivedDataPath $(XCBUILD) build
	@mkdir -p $(DIST)
	@cp -R $(XCBUILD)/Build/Products/Release/Parla.app $(DIST)/
	@codesign --force --sign - --timestamp=none $(DIST)/Parla.app
	@codesign --verify --strict --verbose=2 $(DIST)/Parla.app
	@v=$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
	  $(DIST)/Parla.app/Contents/Info.plist); \
	  cd $(DIST) && ditto -c -k --keepParent Parla.app Parla-$$v.zip && \
	  echo "" && echo "Listo: dist/Parla-$$v.zip ($$(du -h Parla-$$v.zip | cut -f1))"

clean:
	rm -rf $(DIST) $(XCBUILD) Core/.build

open: generate
	open Parla.xcodeproj
