APP=build/Build/Products/Debug/Ergo.app

gen:
	xcodegen generate

build: gen
	xcodebuild -project Ergo.xcodeproj -scheme Ergo -configuration Debug -derivedDataPath build build

run: build
	-pkill -x Ergo
	open $(APP)

test:
	swift test --package-path Packages/ErgoKit

clean:
	rm -rf build Packages/ErgoKit/.build Ergo.xcodeproj
