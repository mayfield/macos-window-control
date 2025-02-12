SC_FLAGS := -Osize 


build: cli c-lib
	npm install

cli: dist
	swiftc src/core.swift src/main.swift -target arm64-apple-macos11 $(SC_FLAGS) -o dist/.macos-window-control.arm64
	swiftc src/core.swift src/main.swift -target x86_64-apple-macos11 $(SC_FLAGS) -o dist/.macos-window-control.x86_64
	lipo -create dist/.macos-window-control.arm64 dist/.macos-window-control.x86_64 -output dist/macos-window-control

c-lib: dist
	cd obj ; \
	swiftc ../src/core.swift ../src/c-lib.swift -emit-library -target arm64-apple-macos11 $(SC_FLAGS) -static -o .mwc.a.arm64
	#swiftc src/core.swift -emit-library -target x86_64-apple-macos11 $(SC_FLAGS) -static -o obj/.mwc.a.x86_64
	#lipo -create obj/.mwc.a.arm64 obj/.mwc.a.x86_64 -output obj/mwc.a


obj:
	mkdir -p obj

dist:
	mkdir -p dist

clean:
	rm -rf dist obj
