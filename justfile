set shell := ["zsh", "-cu"]

default:
    @just --list

generate:
    xcodegen generate

build-macos: generate
    xcodebuild -project Nutrition.xcodeproj -scheme Nutrition -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/xcode build CODE_SIGNING_ALLOWED=NO

test-macos: generate
    xcodebuild -project Nutrition.xcodeproj -scheme Nutrition -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/xcode test CODE_SIGNING_ALLOWED=NO

run-macos: build-macos
    ../../tools/apple-app.sh run-macos "$PWD" Nutrition com.productivitysuite.nutrition

install-macos: release-macos
    ../../tools/apple-app.sh install-macos "$PWD" Nutrition com.productivitysuite.nutrition

release-macos: generate
    xcodebuild -project Nutrition.xcodeproj -scheme Nutrition -configuration Release -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/xcode build CODE_SIGNING_ALLOWED=NO

build-sim: generate
    ../../tools/apple-app.sh build-sim "$PWD" Nutrition NutritionIOS com.productivitysuite.nutrition.ios

test-sim: generate
    ../../tools/apple-app.sh test-sim "$PWD" Nutrition NutritionIOS com.productivitysuite.nutrition.ios

run-sim: generate
    ../../tools/apple-app.sh run-sim "$PWD" Nutrition NutritionIOS com.productivitysuite.nutrition.ios

build-device: generate
    ../../tools/apple-app.sh build-device "$PWD" Nutrition NutritionIOS com.productivitysuite.nutrition.ios

install-device: generate
    ../../tools/apple-app.sh install-device "$PWD" Nutrition NutritionIOS com.productivitysuite.nutrition.ios

run-device: generate
    ../../tools/apple-app.sh run-device "$PWD" Nutrition NutritionIOS com.productivitysuite.nutrition.ios

update-icon picture:
    Tools/update-app-icon.sh "{{picture}}"

icons:
    @echo "Lucide icons are bundled by packages/ProductivityUI"

build: build-macos
test: test-macos
run: run-macos
release: release-macos
