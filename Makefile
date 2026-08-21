.PHONY: generate build run test clean

DERIVED := .build
APP := Murmur

generate:
	xcodegen generate

build: generate
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Debug -derivedDataPath $(DERIVED) -quiet build

run: build
	open $(DERIVED)/Build/Products/Debug/$(APP).app

test: generate
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Debug -derivedDataPath $(DERIVED) test

clean:
	rm -rf $(DERIVED) $(APP).xcodeproj
