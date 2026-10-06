set shell := ["zsh", "-cu"]

default:
    @just --list

generate:
    xcodegen generate

build: generate
    mkdir -p .build/xcode
    xcodebuild -project Nutrition.xcodeproj -scheme Nutrition -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/xcode build CODE_SIGNING_ALLOWED=NO

test: generate
    mkdir -p .build/xcode
    xcodebuild -project Nutrition.xcodeproj -scheme Nutrition -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/xcode test CODE_SIGNING_ALLOWED=NO

open:
    open -n -F .build/xcode/Build/Products/Debug/Nutrition.app

run: build
    just open

release: generate
    mkdir -p .build/xcode
    xcodebuild -project Nutrition.xcodeproj -scheme Nutrition -configuration Release -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/xcode build CODE_SIGNING_ALLOWED=NO

icons:
    zsh Tools/fetch-lucide-icons.sh

mobile-build: generate
    mkdir -p .build/mobile
    xcodebuild -project Nutrition.xcodeproj -scheme NutritionMobile -configuration Debug -sdk iphonesimulator -derivedDataPath .build/mobile build CODE_SIGNING_ALLOWED=NO

mobile-test: generate
    mkdir -p .build/mobile
    xcodebuild -project Nutrition.xcodeproj -scheme NutritionMobile -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17" -derivedDataPath .build/mobile test CODE_SIGNING_ALLOWED=NO

mobile-release: generate
    mkdir -p .build/mobile-release
    xcodebuild -project Nutrition.xcodeproj -scheme NutritionMobile -configuration Release -sdk iphonesimulator -derivedDataPath .build/mobile-release build CODE_SIGNING_ALLOWED=NO

update-icon picture:
    zsh Native/Tools/update-app-icon.sh "{{picture}}"
