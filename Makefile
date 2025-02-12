SC_FLAGS := -Osize 


all: cli
	npm install

cli: .obj
	swiftc src/core.swift src/main.swift -target arm64-apple-macos11 $(SC_FLAGS) -o .obj/macos-window-control.arm64
	swiftc src/core.swift src/main.swift -target x86_64-apple-macos11 $(SC_FLAGS) -o .obj/macos-window-control.x86_64
	lipo -create .obj/macos-window-control.arm64 .obj/macos-window-control.x86_64 -output macos-window-control

c-lib: .obj
	swiftc src/core.swift src/c-lib.swift -emit-library -target arm64-apple-macos11 $(SC_FLAGS) -static -o .obj/mwc.a.arm64
	swiftc src/core.swift src/c-lib.swift -emit-library -target x86_64-apple-macos11 $(SC_FLAGS) -static -o .obj/mwc.a.x86_64
	lipo -create .obj/mwc.a.arm64 .obj/mwc.a.x86_64 -output .obj/mwc.a

.obj:
	mkdir -p .obj

clean:
	rm -rf build .obj
