# Quick Camera +QR

This is a fork from [Quick Camera](https://github.com/simonguest/quick-camera). Thanks to the author for making such an efficient, reliable camera utility.  
We plan to add QR code reading functionality by utilizing [Zbar](https://github.com/mchehab/zbar?utm_source=chatgpt.com) as the backend.

Quick Camera is a macOS utility to display the output from any USB-based camera on your desktop. Quick Camera is often used for presentations where you need to show the output from an external device to your audience. 

Quick Camera supports mirroring (normal and reversed, both vertical and horizontal), can be rotated, resized to any size, and the window can be placed in the foreground.

<!-- toc -->

- [Motivation](#motivation)
- [Objective](#objective)
- [Build](#build)

<!-- tocstop -->

## Motivation

It seems like currently there's no FOSS lightweight QR code reader for macOS. I use QR codes day-to-day for sending Wi-Fi passwords, web links, draft sentences, etc., since they're minimal and just work.  
I've been using Quick Camera because it's lightweight and reliable. In addition, it's a saintly FOSS. One thing that I'd been missing for the software is just the QR code reading functionality.  
For a while, I was just hoping someone would add it. But wait... I'm a programmer too. And I realized my cousin can build apps for macOS. So why don't we build it ourselves?

## Objective

Our objective for this app development is pretty simple. **Just adding QR code reading functionality to the upstream**.
Keeping it simple, separation of concerns.  
Optimally, bringing the same lightweight and efficient experience as the upstream provides.

You can find the original app on the Mac App Store: https://itunes.apple.com/us/app/qcamera/id598853070?mt=12

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
