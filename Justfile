# Justfile for Syncable-Swift

# List available recipes
default:
    @just --list

# Build the package
build:
    swift build

# Run all tests
test:
    swift test

# Clean build artifacts
clean:
    swift package clean

# Update package dependencies
update:
    swift package update

# Generate Xcode project (legacy)
generate-xcodeproj:
    swift package generate-xcodeproj
