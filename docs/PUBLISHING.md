# Publishing Guide

Guide for publishing the Conferbot iOS SDK to CocoaPods and Swift Package Manager.

## Prerequisites

- Xcode 14.0+
- CocoaPods 1.11.0+ (for CocoaPods release)
- Git repository with proper structure
- Apple Developer account (for testing)
- GitHub account (for releases)

## Pre-Release Checklist

- [ ] All tests passing
- [ ] Documentation complete
- [ ] CHANGELOG.md updated
- [ ] Version numbers updated
- [ ] Example app tested
- [ ] README.md reviewed
- [ ] License file present
- [ ] .gitignore configured

## Version Numbering

Follow Semantic Versioning (SemVer):

- **MAJOR**: Breaking API changes
- **MINOR**: New features (backwards compatible)
- **PATCH**: Bug fixes (backwards compatible)

Example: `1.2.3`

## Swift Package Manager

### 1. Prepare Repository

```bash
cd /path/to/conferbot-ios

# Ensure Package.swift is correct
cat Package.swift

# Tag version
git tag 1.0.0
git push origin 1.0.0
```

### 2. Create GitHub Release

1. Go to GitHub repository
2. Click "Releases" → "Create a new release"
3. Choose tag: `1.0.0`
4. Release title: `v1.0.0 - Initial Release`
5. Description: Copy from CHANGELOG.md
6. Attach any binary assets (optional)
7. Publish release

### 3. Test SPM Installation

Create a test project:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/conferbot/conferbot-ios", from: "1.0.0")
]
```

Or in Xcode:
1. File → Add Packages
2. Enter repository URL
3. Select version
4. Verify it builds

## CocoaPods

### 1. Register CocoaPods Account

First time only:

```bash
pod trunk register your-email@conferbot.com 'Your Name' --description='Conferbot SDK'

# Verify email
# Click link in email
```

### 2. Validate Podspec

```bash
cd /path/to/conferbot-ios

# Lint locally
pod lib lint Conferbot.podspec --allow-warnings

# Lint remotely (after pushing to GitHub)
pod spec lint Conferbot.podspec --allow-warnings
```

### 3. Push to CocoaPods

```bash
# Push to trunk
pod trunk push Conferbot.podspec --allow-warnings

# This will:
# 1. Validate podspec
# 2. Build library
# 3. Run tests
# 4. Publish to CocoaPods
```

### 4. Verify Publication

```bash
# Search for pod
pod search Conferbot

# Check pod info
pod trunk info Conferbot
```

### 5. Test Installation

Create `Podfile`:

```ruby
platform :ios, '13.0'
use_frameworks!

target 'TestApp' do
  pod 'Conferbot', '~> 1.0'
end
```

Install:

```bash
pod install
```

## Building for Release

### 1. Clean Build

```bash
cd /path/to/conferbot-ios

# Clean
rm -rf ~/Library/Developer/Xcode/DerivedData
xcodebuild clean

# Build
xcodebuild \
  -scheme Conferbot \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  build
```

### 2. Archive Framework

For XCFramework distribution:

```bash
# Build for iOS devices
xcodebuild archive \
  -scheme Conferbot \
  -destination 'generic/platform=iOS' \
  -archivePath './build/ios.xcarchive' \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# Build for iOS Simulator
xcodebuild archive \
  -scheme Conferbot \
  -destination 'generic/platform=iOS Simulator' \
  -archivePath './build/ios-simulator.xcarchive' \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# Create XCFramework
xcodebuild -create-xcframework \
  -archive './build/ios.xcarchive' -framework Conferbot.framework \
  -archive './build/ios-simulator.xcarchive' -framework Conferbot.framework \
  -output './build/Conferbot.xcframework'
```

### 3. Package for Distribution

```bash
# Create zip
cd build
zip -r Conferbot-1.0.0.xcframework.zip Conferbot.xcframework

# Calculate checksum
shasum -a 256 Conferbot-1.0.0.xcframework.zip
```

## GitHub Release Assets

### Upload XCFramework

1. Go to GitHub release
2. Edit release
3. Upload `Conferbot-1.0.0.xcframework.zip`
4. Add checksum to release notes

### Binary Framework Distribution

Update `Package.swift` for binary distribution:

```swift
.binaryTarget(
    name: "Conferbot",
    url: "https://github.com/conferbot/conferbot-ios/releases/download/1.0.0/Conferbot-1.0.0.xcframework.zip",
    checksum: "sha256-checksum-here"
)
```

## Documentation Publishing

### DocC Documentation

```bash
# Generate documentation
xcodebuild docbuild \
  -scheme Conferbot \
  -destination 'generic/platform=iOS'

# Find generated docc archive
find ~/Library/Developer/Xcode/DerivedData -name "Conferbot.doccarchive"

# Host on GitHub Pages
# 1. Convert to static website
# 2. Push to gh-pages branch
```

### Jazzy Documentation

Alternative using Jazzy:

```bash
# Install Jazzy
gem install jazzy

# Generate docs
jazzy \
  --module Conferbot \
  --swift-build-tool spm \
  --output docs/api

# Upload to hosting
```

## Marketing Assets

### App Store Screenshots

For apps using the SDK, create:
- Chat interface screenshots
- Feature highlights
- Before/after comparison

### Social Media

- Announcement tweet
- LinkedIn post
- Product Hunt launch
- Dev.to article

### Press Release

Template:

```
Conferbot Releases Native iOS SDK

[City, Date] - Conferbot today announced the release of its native iOS SDK,
enabling iOS developers to integrate AI-powered customer support chat into
their applications with just a few lines of code.

Key Features:
- Native Swift implementation
- Real-time Socket.IO communication
- UIKit and SwiftUI support
- Full customization
- Push notifications
- Offline support

The SDK is available now via CocoaPods and Swift Package Manager.

About Conferbot:
[Company description]

Contact:
[Contact information]
```

## Update Documentation Sites

### Main Website

Update:
- `/docs/mobile/ios` section
- Integration guide
- API reference
- Code examples

### Developer Portal

- Installation guide
- Quick start
- API documentation
- Migration guides

### Community

- Discord announcement
- GitHub Discussions post
- Stack Overflow tag creation

## Monitor Release

### Track Adoption

- CocoaPods stats: `pod stats Conferbot`
- GitHub stars and watchers
- Download counts from releases

### Handle Issues

- Monitor GitHub Issues
- Check Stack Overflow questions
- Discord support channel
- Email support tickets

### Collect Feedback

- Survey early adopters
- Feature requests
- Bug reports
- Performance issues

## Maintenance Releases

### Patch Release (1.0.1)

For bug fixes:

```bash
# 1. Fix bugs
# 2. Update version
# 3. Update CHANGELOG.md
# 4. Create tag
git tag 1.0.1
git push origin 1.0.1

# 5. Update podspec version
# 6. Push to CocoaPods
pod trunk push Conferbot.podspec

# 7. Create GitHub release
```

### Minor Release (1.1.0)

For new features:

```bash
# 1. Develop features
# 2. Update documentation
# 3. Update examples
# 4. Update version
# 5. Update CHANGELOG.md
# 6. Test thoroughly
# 7. Release (same steps as above)
```

### Major Release (2.0.0)

For breaking changes:

```bash
# 1. Document breaking changes
# 2. Create migration guide
# 3. Update all examples
# 4. Bump major version
# 5. Deprecation warnings in 1.x
# 6. Release 2.0.0
```

## Rollback Procedure

If critical issue found:

### 1. Yank Release

CocoaPods:
```bash
pod trunk delete Conferbot 1.0.0
```

GitHub:
- Edit release
- Mark as "Pre-release"
- Add warning to description

### 2. Hotfix Release

```bash
# Create hotfix branch
git checkout -b hotfix/1.0.1 v1.0.0

# Fix issue
git commit -m "Fix critical issue"

# Tag and release
git tag 1.0.1
git push origin 1.0.1

# Release 1.0.1
```

### 3. Communicate

- Email users
- GitHub announcement
- Discord notification
- Status page update

## Legal Checklist

- [ ] License file included
- [ ] Third-party licenses documented
- [ ] Privacy policy updated
- [ ] Terms of service reviewed
- [ ] Export compliance verified
- [ ] Trademark usage correct

## Quality Gates

Before releasing, ensure:

### Code Quality
- [ ] All tests pass (unit, integration, UI)
- [ ] Code coverage > 80%
- [ ] No SwiftLint warnings
- [ ] Memory leaks checked
- [ ] Performance profiled

### Documentation
- [ ] API docs complete
- [ ] Examples working
- [ ] README accurate
- [ ] CHANGELOG updated
- [ ] Migration guide (if breaking)

### Compatibility
- [ ] iOS 13+ tested
- [ ] Xcode 14+ builds
- [ ] Swift 5.7+ compatible
- [ ] CocoaPods installs
- [ ] SPM installs

### Distribution
- [ ] Podspec valid
- [ ] Package.swift correct
- [ ] Tags pushed
- [ ] Release notes written
- [ ] Binary uploaded (if applicable)

## Post-Release Tasks

### Week 1
- [ ] Monitor crash reports
- [ ] Answer support questions
- [ ] Fix critical bugs
- [ ] Write blog post

### Month 1
- [ ] Analyze adoption metrics
- [ ] Collect user feedback
- [ ] Plan next release
- [ ] Update roadmap

### Quarter 1
- [ ] Major feature development
- [ ] Community engagement
- [ ] Conference talks
- [ ] Case studies

## Automation

### CI/CD Pipeline

GitHub Actions workflow:

```yaml
name: Release

on:
  push:
    tags:
      - '*'

jobs:
  release:
    runs-on: macos-latest

    steps:
      - uses: actions/checkout@v3

      - name: Build
        run: xcodebuild -scheme Conferbot build

      - name: Test
        run: xcodebuild -scheme Conferbot test

      - name: Validate Podspec
        run: pod lib lint

      - name: Create Release
        uses: actions/create-release@v1
        with:
          tag_name: ${{ github.ref }}
          release_name: Release ${{ github.ref }}
```

### Auto-versioning

Script to bump version:

```bash
#!/bin/bash
# bump-version.sh

VERSION=$1

# Update podspec
sed -i '' "s/s.version *= *'.*'/s.version = '$VERSION'/" Conferbot.podspec

# Update Package.swift (if needed)

# Commit
git add .
git commit -m "Bump version to $VERSION"
git tag $VERSION
git push origin main $VERSION
```

## Support Channels

After release, monitor:
- GitHub Issues
- Discord #ios-sdk
- Stack Overflow [conferbot-ios]
- Email: ios-sdk@conferbot.com
- Twitter mentions

## Success Metrics

Track:
- Install count (CocoaPods + SPM)
- GitHub stars
- Active users (through SDK analytics)
- Support ticket volume
- Developer satisfaction score
- Documentation page views

## Resources

- [CocoaPods Guides](https://guides.cocoapods.org/)
- [Swift Package Manager](https://swift.org/package-manager/)
- [Semantic Versioning](https://semver.org/)
- [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github)
