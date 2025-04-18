#SC_FLAGS := -O -g
SC_FLAGS := -O \
	-warnings-as-errors
C_LIB_FLAGS := -emit-library -static \
	-Xcc -std=gnu++11 -cxx-interoperability-mode=default \
	-emit-clang-header-path obj/c-lib.swift.h
CLI := macos-window-control

SRCS := $(wildcard src/*)
TESTS := $(wildcard test/*)
OBJ := obj
NODE_BUILD := .node-build

ifeq ($(ARCH), x64)
  override ARCH := x86_64
endif


default: $(CLI) node-build

########

node-build: $(NODE_BUILD)

$(NODE_BUILD): $(SRCS) Makefile node_modules
	#npm rebuild --debug
	npm rebuild
	touch $@

node_modules:
	npm install

cli: $(CLI)

$(CLI): $(SRCS) Makefile
	swiftc src/core.swift src/main.swift -target arm64-apple-macos11 $(SC_FLAGS) -o $(OBJ)/$(CLI).arm64
	swiftc src/core.swift src/main.swift -target x86_64-apple-macos11 $(SC_FLAGS) -o $(OBJ)/$(CLI).x86_64
	lipo -create $(OBJ)/$(CLI).arm64 $(OBJ)/$(CLI).x86_64 -output $(CLI)

c-lib: $(SRCS) Makefile
	swiftc src/core.swift src/c-lib.swift -target $(ARCH)-apple-macos11 $(SC_FLAGS) $(C_LIB_FLAGS) -o $(OBJ)/mwc.a

test: $(TESTS) Makefile node-build
	node --test 'test/*'

clean:
	rm -rf build $(OBJ)/* $(NODE_BUILD)

realclean: clean
	rm -rf node_modules

########

.PHONY: clean realclean test
