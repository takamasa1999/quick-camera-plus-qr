# Development

Here are some notes on building and developing Quick Camera.

<!-- toc -->

- [Todo](#todo)
- [Build](#build)

<!-- tocstop -->

## Todo

- Code refactoring, separate files for different functionalities.
- Performance optimizations for the increase of memory usage.
- QR reading performance enhancements under low-light conditions.

## Build

Quick Camera can be built using XCode. Download XCode from https://developer.apple.com/xcode/ and open the Quick Camera.xcodeproj file.

In addition, with XCode or the XCode Command Line Tools installed, Quick Camera can also be built using the command line:

```bash
xcodebuild -scheme Quick\ Camera -configuration Release clean build
```

Upon successful build, Quick Camera can be launched with:

```bash
open build/release/Quick\ Camera.app
```

Finally, a Package.swift file is included for building Quick Camera using Swift Package Manager. This, however, is designed only to support editing Quick Camera in VS Code (via the Swift Language Support extension and LSP).
