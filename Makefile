DEVDIR := $(shell xcode-select -p)
XFRAMEWORKS := $(DEVDIR)/Library/Developer/Frameworks
XLIBS := $(DEVDIR)/Library/Developer/usr/lib

# Solo Command Line Tools necesita ayuda para encontrar swift-testing.
TESTFLAGS := $(if $(wildcard $(XLIBS)/lib_TestingInterop.dylib), \
  -Xswiftc -F -Xswiftc $(XFRAMEWORKS) \
  -Xlinker -F -Xlinker $(XFRAMEWORKS) \
  -Xlinker -rpath -Xlinker $(XFRAMEWORKS) \
  -Xlinker -rpath -Xlinker $(XLIBS),)

.PHONY: test generate build run install open

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

open: generate
	open Parla.xcodeproj
