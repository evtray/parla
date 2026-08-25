DEVDIR := $(shell xcode-select -p)
XFRAMEWORKS := $(DEVDIR)/Library/Developer/Frameworks
XLIBS := $(DEVDIR)/Library/Developer/usr/lib

# Solo Command Line Tools necesita ayuda para encontrar swift-testing.
TESTFLAGS := $(if $(wildcard $(XLIBS)/lib_TestingInterop.dylib), \
  -Xswiftc -F -Xswiftc $(XFRAMEWORKS) \
  -Xlinker -F -Xlinker $(XFRAMEWORKS) \
  -Xlinker -rpath -Xlinker $(XFRAMEWORKS) \
  -Xlinker -rpath -Xlinker $(XLIBS),)

.PHONY: test generate open

test:
	cd Core && swift test $(TESTFLAGS)

generate:
	xcodegen generate

open: generate
	open Parla.xcodeproj
