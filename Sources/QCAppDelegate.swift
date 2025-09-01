import AVKit
import Cocoa

// MARK: - QCAppDelegate Class
@NSApplicationMain
class QCAppDelegate: NSObject, NSApplicationDelegate, QCUsbWatcherDelegate,
    AVCaptureVideoDataOutputSampleBufferDelegate, QCQRCodeReaderDelegate
{
    // MARK: - USB Watcher
    let usb: QCUsbWatcher = QCUsbWatcher()
    func deviceCountChanged() {
        self.detectVideoDevices()
        self.startCaptureWithVideoDevice(defaultDevice: selectedDeviceIndex)
    }

    private var videoOutput: AVCaptureVideoDataOutput?

    // MARK: - Interface Builder Outlets
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var selectSourceMenu: NSMenuItem!
    @IBOutlet weak var borderlessMenu: NSMenuItem!
    @IBOutlet weak var aspectRatioFixedMenu: NSMenuItem!
    @IBOutlet weak var mirroredMenu: NSMenuItem!
    @IBOutlet weak var upsideDownMenu: NSMenuItem!
    @IBOutlet weak var playerView: NSView!
    @IBOutlet weak var qrReadingDisableMenuItem: NSMenuItem!

    // MARK: - QR Code Reading
    private let qrReader = QCQRCodeReader()

    // MARK: - Settings Properties
    var isMirrored: Bool {
        get { QCSettingsManager.shared.isMirrored }
        set { QCSettingsManager.shared.setMirrored(newValue) }
    }
    var isUpsideDown: Bool {
        get { QCSettingsManager.shared.isUpsideDown }
        set { QCSettingsManager.shared.setUpsideDown(newValue) }
    }
    var position: Int {
        get { QCSettingsManager.shared.position }
        set { QCSettingsManager.shared.setPosition(newValue) }
    }
    var isBorderless: Bool {
        get { QCSettingsManager.shared.isBorderless }
        set { QCSettingsManager.shared.setBorderless(newValue) }
    }
    var isAspectRatioFixed: Bool {
        get { QCSettingsManager.shared.isAspectRatioFixed }
        set { QCSettingsManager.shared.setAspectRatioFixed(newValue) }
    }
    var deviceName: String {
        get { QCSettingsManager.shared.deviceName }
        set { QCSettingsManager.shared.setDeviceName(newValue) }
    }
    var isQRReadingEnabled: Bool {
        get { QCSettingsManager.shared.isQRCodeReadingEnabled }
        set { QCSettingsManager.shared.setQRCodeReadingEnabled(newValue) }
    }

    // MARK: - Window Properties
    var defaultBorderStyle: NSWindow.StyleMask = NSWindow.StyleMask.closable
    var windowTitle: String = "Quick Camera"
    let defaultDeviceIndex: Int = 0
    var selectedDeviceIndex: Int = 0

    var savedDeviceName: String = "-"
    var devices: [AVCaptureDevice]!
    var captureSession: AVCaptureSession!
    var captureLayer: AVCaptureVideoPreviewLayer!

    var input: AVCaptureDeviceInput!

    // QR Prompt Control
    private var isQRPromptActive = false
    private var lastPromptedAt: Date? = nil
    private let promptCooldown: TimeInterval = 1.0

    // MARK: - Error Handling
    func errorMessage(message: String) {
        let popup: NSAlert = NSAlert()
        popup.messageText = message
        popup.runModal()
    }

    // MARK: - Device Management
    func detectVideoDevices() {
        NSLog("Detecting video devices...")
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified)
        self.devices = discoverySession.devices
        if devices.isEmpty {
            let popup: NSAlert = NSAlert()
            popup.messageText =
                "Unfortunately, you don't appear to have any cameras connected. Goodbye for now!"
            popup.runModal()
            NSApp.terminate(nil)
        } else {
            NSLog("%d devices found", devices.count)
        }

        let deviceMenu: NSMenu = NSMenu()
        var deviceIndex: Int = 0

        // Here we need to keep track of the current device (if selected) in order to keep it checked in the menu
        var currentDevice: AVCaptureDevice = self.devices[defaultDeviceIndex]
        if self.captureSession != nil {
            currentDevice = (self.captureSession.inputs[0] as! AVCaptureDeviceInput).device
        } else {
            NSLog("first time - loadSettings")
            self.loadSettings()
        }
        self.selectedDeviceIndex = defaultDeviceIndex

        for device: AVCaptureDevice in self.devices {
            let deviceMenuItem: NSMenuItem = NSMenuItem(
                title: device.localizedName, action: #selector(deviceMenuChanged), keyEquivalent: ""
            )
            deviceMenuItem.target = self
            deviceMenuItem.representedObject = deviceIndex
            if device == currentDevice {
                deviceMenuItem.state = NSControl.StateValue.on
                self.selectedDeviceIndex = deviceIndex
            }
            if deviceIndex < 9 {
                deviceMenuItem.keyEquivalent = String(deviceIndex + 1)
            }
            deviceMenu.addItem(deviceMenuItem)
            deviceIndex += 1
        }
        selectSourceMenu.submenu = deviceMenu
    }

    func startCaptureWithVideoDevice(defaultDevice: Int) {
        NSLog("Starting capture with device index %d", defaultDevice)
        let device: AVCaptureDevice = self.devices[defaultDevice]

        if captureSession != nil {

            // if we are "restarting" a session but the device is the same exit early
            let currentDevice: AVCaptureDevice =
                (self.captureSession.inputs[0] as! AVCaptureDeviceInput).device
            guard currentDevice != device else { return }

            captureSession.stopRunning()
        }
        captureSession = AVCaptureSession()

        do {
            self.input = try AVCaptureDeviceInput(device: device)
            self.captureSession.addInput(input)

            // Set up video output for QR code reading
            setupVideoOutput()

            self.captureSession.startRunning()
            self.captureLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
            self.captureLayer.connection?.automaticallyAdjustsVideoMirroring = false
            self.captureLayer.connection?.isVideoMirrored = false

            self.playerView.layer = self.captureLayer
            self.playerView.layer?.backgroundColor = CGColor.black
            self.windowTitle = String(format: "Quick Camera +QR: [%@]", device.localizedName)
            self.window.title = self.windowTitle
            self.deviceName = device.localizedName
            self.applySettings()
        } catch {
            NSLog("Error while opening device")
            self.errorMessage(
                message:
                    "Unfortunately, there was an error when trying to access the camera. Try again or select a different one."
            )
        }
    }

    private func setupVideoOutput() {
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput?.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: .userInitiated))

        if let videoOutput = videoOutput {
            captureSession.addOutput(videoOutput)
        }

        // Configure QR code reader
        qrReader.delegate = self
    }

    // MARK: - Settings Management
    func logSettings(label: String) {
        QCSettingsManager.shared.logSettings(label: label)
    }

    func loadSettings() {
        QCSettingsManager.shared.loadSettings()

        if self.isBorderless {
            self.removeBorder()
        }

        let savedW = QCSettingsManager.shared.frameWidth
        let savedH = QCSettingsManager.shared.frameHeight
        if 100 < savedW && 100 < savedH {
            let savedX = QCSettingsManager.shared.frameX
            let savedY = QCSettingsManager.shared.frameY
            NSLog("loaded : x:%f,y:%f,w:%f,h:%f", savedX, savedY, savedW, savedH)
            var currentSize: CGSize = self.window.contentLayoutRect.size
            currentSize.width = CGFloat(savedW)
            currentSize.height = CGFloat(savedH)
            self.window.setContentSize(currentSize)
            self.window.setFrameOrigin(NSPoint(x: CGFloat(savedX), y: CGFloat(savedY)))
        }
    }

    func applySettings() {
        QCSettingsManager.shared.logSettings(label: "applySettings")

        self.setRotation(self.position)
        self.captureLayer.connection?.isVideoMirrored = isMirrored
        self.fixAspectRatio()

        self.borderlessMenu.state = convertToNSControlStateValue(
            (isBorderless ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
        self.mirroredMenu.state = convertToNSControlStateValue(
            (isMirrored ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
        self.upsideDownMenu.state = convertToNSControlStateValue(
            (isUpsideDown ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
        self.aspectRatioFixedMenu.state = convertToNSControlStateValue(
            (isAspectRatioFixed
                ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))

        self.qrReadingDisableMenuItem.state = convertToNSControlStateValue(
            (!isQRReadingEnabled
                ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
    }

    // MARK: - Settings Actions
    @IBAction func saveSettings(_ sender: NSMenuItem) {
        QCSettingsManager.shared.setFrameProperties(
            x: Float(self.window.frame.minX),
            y: Float(self.window.frame.minY),
            width: Float(self.window.frame.width),
            height: Float(self.window.frame.height)
        )
        QCSettingsManager.shared.saveSettings()
    }

    @IBAction func clearSettings(_ sender: NSMenuItem) {
        QCSettingsManager.shared.clearSettings()
    }

    // MARK: - Display Actions
    @IBAction func mirrorHorizontally(_ sender: NSMenuItem) {
        NSLog("Mirror image menu item selected")
        isMirrored = !isMirrored
        self.applySettings()
    }

    func setRotation(_ position: Int) {
        switch position {
        case 1:
            if !isUpsideDown {
                self.captureLayer.connection?.videoOrientation =
                    AVCaptureVideoOrientation.landscapeLeft
            } else {
                self.captureLayer.connection?.videoOrientation =
                    AVCaptureVideoOrientation.landscapeRight
            }
            break
        case 2:
            if !isUpsideDown {
                self.captureLayer.connection?.videoOrientation =
                    AVCaptureVideoOrientation.portraitUpsideDown
            } else {
                self.captureLayer.connection?.videoOrientation = AVCaptureVideoOrientation.portrait
            }
            break
        case 3:
            if !isUpsideDown {
                self.captureLayer.connection?.videoOrientation =
                    AVCaptureVideoOrientation.landscapeRight
            } else {
                self.captureLayer.connection?.videoOrientation =
                    AVCaptureVideoOrientation.landscapeLeft
            }
            break
        case 0:
            if !isUpsideDown {
                self.captureLayer.connection?.videoOrientation = AVCaptureVideoOrientation.portrait
            } else {
                self.captureLayer.connection?.videoOrientation =
                    AVCaptureVideoOrientation.portraitUpsideDown
            }
            break
        default: break
        }
    }

    @IBAction func mirrorVertically(_ sender: NSMenuItem) {
        NSLog("Mirror image vertically menu item selected")
        isUpsideDown = !isUpsideDown
        self.applySettings()
    }

    func swapWH() {
        var currentSize: CGSize = self.window.contentLayoutRect.size
        swap(&currentSize.height, &currentSize.width)
        self.window.setContentSize(currentSize)
    }

    @IBAction func rotateLeft(_ sender: NSMenuItem) {
        NSLog("Rotate Left menu item selected with position %d", position)
        position = position - 1
        if position == -1 { position = 3 }
        self.swapWH()
        self.applySettings()
    }

    @IBAction func rotateRight(_ sender: NSMenuItem) {
        NSLog("Rotate Right menu item selected with position %d", position)
        position = position + 1
        if position == 4 { position = 0 }
        self.swapWH()
        self.applySettings()
    }

    // MARK: - Display Helpers
    private func addBorder() {
        window.styleMask = defaultBorderStyle
        window.title = self.windowTitle
        self.window.level = convertToNSWindowLevel(Int(CGWindowLevelForKey(.normalWindow)))
        window.isMovableByWindowBackground = false
    }

    private func removeBorder() {
        defaultBorderStyle = window.styleMask
        self.window.styleMask = [NSWindow.StyleMask.borderless, NSWindow.StyleMask.resizable]
        self.window.level = convertToNSWindowLevel(Int(CGWindowLevelForKey(.maximumWindow)))
        window.isMovableByWindowBackground = true
    }

    @IBAction func borderless(_ sender: NSMenuItem) {
        NSLog("Borderless menu item selected")
        if self.window.styleMask.contains(.fullScreen) {
            NSLog("Ignoring borderless command as window is full screen")
            return
        }
        isBorderless = !isBorderless
        sender.state = convertToNSControlStateValue(
            (isBorderless ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
        if isBorderless {
            removeBorder()
        } else {
            addBorder()
        }
        fixAspectRatio()
    }

    @IBAction func enterFullScreen(_ sender: NSMenuItem) {
        NSLog("Enter full screen menu item selected")
        playerView.window?.toggleFullScreen(self)
        // no effect when borderless is enabled ?
    }

    @IBAction func toggleFixAspectRatio(_ sender: NSMenuItem) {
        isAspectRatioFixed = !isAspectRatioFixed
        sender.state = convertToNSControlStateValue(
            (isAspectRatioFixed
                ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue))
        fixAspectRatio()
    }

    func isLandscape() -> Bool {
        return position % 2 == 0
    }

    func fixAspectRatio() {
        if isAspectRatioFixed, #available(OSX 10.15, *) {
            let height: Int32 = input.device.activeFormat.formatDescription.dimensions.height
            let width: Int32 = input.device.activeFormat.formatDescription.dimensions.width
            let size: NSSize =
                self.isLandscape()
                ? NSMakeSize(CGFloat(width), CGFloat(height))
                : NSMakeSize(CGFloat(height), CGFloat(width))
            self.window.contentAspectRatio = size

            let ratio: CGFloat = CGFloat(Float(width) / Float(height))
            var currentSize: CGSize = self.window.contentLayoutRect.size
            if self.isLandscape() {
                currentSize.height = currentSize.width / ratio
            } else {
                currentSize.height = currentSize.width * ratio
            }
            NSLog(
                "fixAspectRatio : %f - %d,%d - %f,%f - %f,%f", ratio, width, height, size.width,
                size.height, currentSize.width, currentSize.height)
            self.window.setContentSize(currentSize)
        } else {
            self.window.contentResizeIncrements = NSMakeSize(1.0, 1.0)
        }
    }

    @IBAction func fitToActualSize(_ sender: NSMenuItem) {
        if #available(OSX 10.15, *) {
            let height: Int32 = input.device.activeFormat.formatDescription.dimensions.height
            let width: Int32 = input.device.activeFormat.formatDescription.dimensions.width
            var currentSize: CGSize = self.window.contentLayoutRect.size
            currentSize.width = CGFloat(self.isLandscape() ? width : height)
            currentSize.height = CGFloat(self.isLandscape() ? height : width)
            self.window.setContentSize(currentSize)
        }
    }

    @IBAction func saveImage(_ sender: NSMenuItem) {
        if self.window.styleMask.contains(.fullScreen) {
            NSLog("Save is not supported as window is full screen")
            return
        }

        if captureSession != nil {
            if #available(OSX 10.12, *) {
                // turn borderless on, capture image, return border to previous state
                let borderlessState: Bool = self.isBorderless
                if borderlessState == false {
                    NSLog("Removing border")
                    self.removeBorder()
                }

                /* Pause the RunLoop for 0.1 sec to let the window repaint after removing the border - I'm not a fan of this approach
                   but can't find another way to listen to an event for the window being updated. PRs welcome :) */
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))

                let cgImage: CGImage? = CGWindowListCreateImage(
                    CGRect.null, .optionIncludingWindow, CGWindowID(self.window.windowNumber),
                    [.boundsIgnoreFraming, .bestResolution])

                if borderlessState == false {
                    self.addBorder()
                }

                DispatchQueue.main.async {
                    let now: Date = Date()
                    let dateFormatter: DateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    let date: String = dateFormatter.string(from: now)
                    dateFormatter.dateFormat = "h.mm.ss a"
                    let time: String = dateFormatter.string(from: now)

                    let panel: NSSavePanel = NSSavePanel()
                    panel.nameFieldStringValue = String(
                        format: "Quick Camera Image %@ at %@.png", date, time)
                    panel.beginSheetModal(for: self.window) {
                        (result: NSApplication.ModalResponse) in
                        if result == NSApplication.ModalResponse.OK {
                            NSLog(panel.url!.absoluteString)
                            let destination: CGImageDestination? = CGImageDestinationCreateWithURL(
                                panel.url! as CFURL, UTType.png.identifier as CFString, 1, nil)
                            if destination == nil {
                                NSLog(
                                    "Could not write file - destination returned from CGImageDestinationCreateWithURL was nil"
                                )
                                self.errorMessage(
                                    message:
                                        "Unfortunately, the image could not be saved to this location."
                                )
                            } else {
                                CGImageDestinationAddImage(destination!, cgImage!, nil)
                                CGImageDestinationFinalize(destination!)
                            }
                        }
                    }
                }
            } else {
                let popup: NSAlert = NSAlert()
                popup.messageText =
                    "Unfortunately, saving images is only supported in Mac OSX 10.12 (Sierra) and higher."
                popup.runModal()
            }
        }
    }

    // MARK: - Device Menu Actions
    @objc func deviceMenuChanged(_ sender: NSMenuItem) {
        NSLog("Device Menu changed")
        if sender.state == NSControl.StateValue.on {
            // selected the active device, so nothing to do here
            return
        }

        // set the checkbox on the currently selected device
        for menuItem: NSMenuItem in selectSourceMenu.submenu!.items {
            menuItem.state = NSControl.StateValue.off
        }
        sender.state = NSControl.StateValue.on

        self.startCaptureWithVideoDevice(defaultDevice: sender.representedObject as! Int)
    }

    // MARK: - Application Lifecycle
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        detectVideoDevices()
        startCaptureWithVideoDevice(defaultDevice: defaultDeviceIndex)
        usb.delegate = self
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    // func captureOutput(
    //     _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    //     from connection: AVCaptureConnection
    // ) {
    //     guard isQRReadingEnabled else { return }
    //     qrReader.startReading(from: sampleBuffer)
    // }
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // 1) 機能自体がOFFなら読まない
        guard isQRReadingEnabled else { return }

        // 2) アラート表示中は読まない
        guard !isQRPromptActive else { return }

        // 3) 直近に提示した直後は少しクールダウン（任意）
        if let t = lastPromptedAt, Date().timeIntervalSince(t) < promptCooldown { return }

        qrReader.startReading(from: sampleBuffer)
    }

    // private func presentAlert(
    //     _ alert: NSAlert, handler: @escaping (NSApplication.ModalResponse) -> Void
    // ) {
    //     alert.beginSheetModal(for: self.window, completionHandler: handler)
    // }
    private func presentAlert(
        _ alert: NSAlert,
        completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        isQRPromptActive = true
        NSApp.activate(ignoringOtherApps: true)

        alert.beginSheetModal(for: self.window) { [weak self] resp in
            guard let self = self else { return }
            self.lastPromptedAt = Date()
            self.isQRPromptActive = false
            completion(resp)
        }
    }

    // MARK: - QCQRCodeReaderDelegate
    // func didDetectQRCode(_ code: String) {
    //     DispatchQueue.main.async {
    //         // Check if it's a URL
    //         if self.isValidURL(code) {
    //             let alert = NSAlert()
    //             alert.messageText = "QR Code URL Detected"
    //             alert.informativeText = code
    //             alert.addButton(withTitle: "Open")
    //             alert.addButton(withTitle: "Copy")
    //             alert.addButton(withTitle: "Cancel")
    //
    //             let response = alert.runModal()
    //             if response == .alertFirstButtonReturn {
    //                 // Open URL
    //                 if let url = URL(string: code) {
    //                     NSWorkspace.shared.open(url)
    //                 }
    //             } else if response == .alertSecondButtonReturn {
    //                 // Copy to clipboard
    //                 let pasteboard = NSPasteboard.general
    //                 pasteboard.clearContents()
    //                 pasteboard.setString(code, forType: .string)
    //             }
    //         } else {
    //             // For non-URL content, use standard behavior
    //             let alert = NSAlert()
    //             alert.messageText = "QR Code Detected"
    //             alert.informativeText = code
    //             alert.addButton(withTitle: "Copy")
    //             alert.addButton(withTitle: "OK")
    //
    //             let response = alert.runModal()
    //             if response == .alertFirstButtonReturn {
    //                 let pasteboard = NSPasteboard.general
    //                 pasteboard.clearContents()
    //                 pasteboard.setString(code, forType: .string)
    //             }
    //         }
    //     }
    // }
    func didDetectQRCode(_ code: String) {
        DispatchQueue.main.async {
            if self.isValidURL(code) {
                let alert = NSAlert()
                alert.messageText = "QR Code URL Detected"
                alert.informativeText = code
                alert.addButton(withTitle: "Open")
                alert.addButton(withTitle: "Copy")
                alert.addButton(withTitle: "Cancel")

                self.presentAlert(alert) { response in
                    if response == .alertFirstButtonReturn, let url = URL(string: code) {
                        NSWorkspace.shared.open(url)
                    } else if response == .alertSecondButtonReturn {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    }
                }
            } else {
                let alert = NSAlert()
                alert.messageText = "QR Code Detected"
                alert.informativeText = code
                alert.addButton(withTitle: "Copy")
                alert.addButton(withTitle: "OK")

                self.presentAlert(alert) { response in
                    if response == .alertFirstButtonReturn {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    }
                }
            }
        }
    }

    func didFailToReadQRCode(_ error: Error) {
        NSLog("QR Code reading error: %@", error.localizedDescription)
    }

    // MARK: - URL Validation Helper
    private func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string) else {
            return false
        }

        // Check if URL has valid scheme
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }

        // Define supported schemes
        let supportedSchemes = ["http", "https", "ftp", "ftps", "mailto", "tel"]

        // Check if scheme is supported
        guard supportedSchemes.contains(scheme) else {
            return false
        }

        // For HTTP or HTTPS, check if host exists
        if scheme == "http" || scheme == "https" {
            guard let host = url.host, !host.isEmpty else {
                return false
            }
        }

        return true
    }

    // MARK: - QR Code Control Actions
    @IBAction func toggleQRCodeReading(_ sender: NSMenuItem) {
        isQRReadingEnabled = !isQRReadingEnabled

        if isQRReadingEnabled {
            sender.state = convertToNSControlStateValue(NSControl.StateValue.off.rawValue)

            NSLog("QR Code reading started")
            let alert = NSAlert()
            alert.messageText = "QR Code reading enabled! 💪"
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } else {
            sender.state = convertToNSControlStateValue(NSControl.StateValue.on.rawValue)
            qrReader.stopReading()

            NSLog("QR Code reading stopped")
            let alert = NSAlert()
            alert.messageText = "QR Code reading disabled. 👋"
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

// MARK: - Helper Functions
// Helper function inserted by Swift 4.2 migrator.
private func convertToNSControlStateValue(_ input: Int) -> NSControl.StateValue {
    NSControl.StateValue(rawValue: input)
}

// Helper function inserted by Swift 4.2 migrator.
private func convertToNSWindowLevel(_ input: Int) -> NSWindow.Level {
    NSWindow.Level(rawValue: input)
}
