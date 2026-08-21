.PHONY: generate build run test install clean

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

clean:
	rm -rf $(DERIVED) $(APP).xcodeproj
