.PHONY: generate build run test install bench clean

DERIVED := .build
APP := Murmur

generate:
	xcodegen generate

build: generate
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Debug -derivedDataPath $(DERIVED) -quiet build

run: build
	open $(DERIVED)/Build/Products/Debug/$(APP).app

install: build
	-pkill -x $(APP)
	rm -rf /Applications/$(APP).app
	ditto $(DERIVED)/Build/Products/Debug/$(APP).app /Applications/$(APP).app
	open /Applications/$(APP).app

test: generate
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Debug -derivedDataPath $(DERIVED) test

bench: generate
	xcodebuild -project $(APP).xcodeproj -scheme murmur-bench -configuration Debug -derivedDataPath $(DERIVED) -quiet build
	$(DERIVED)/Build/Products/Debug/murmur-bench bench/fixtures $(BENCH_FLAGS)

clean:
	rm -rf $(DERIVED) $(APP).xcodeproj
