import AVFoundation
import CoreImage
import Foundation

// MARK: - ZBar C Function Declarations
@_silgen_name("zbar_image_scanner_create")
func zbar_image_scanner_create() -> UnsafeMutableRawPointer?

@_silgen_name("zbar_image_scanner_destroy")
func zbar_image_scanner_destroy(_ scanner: UnsafeMutableRawPointer?)

@_silgen_name("zbar_image_scanner_set_config")
func zbar_image_scanner_set_config(
    _ scanner: UnsafeMutableRawPointer?, _ symbology: Int32, _ config: Int32, _ value: Int32
) -> Int32

@_silgen_name("zbar_image_create")
func zbar_image_create() -> UnsafeMutableRawPointer?

@_silgen_name("zbar_image_destroy")
func zbar_image_destroy(_ image: UnsafeMutableRawPointer?)

@_silgen_name("zbar_image_set_data")
func zbar_image_set_data(
    _ image: UnsafeMutableRawPointer?, _ data: UnsafePointer<UInt8>?, _ length: Int, _ format: Int32
)

@_silgen_name("zbar_image_set_format")
func zbar_image_set_format(_ image: UnsafeMutableRawPointer?, _ format: Int32)

@_silgen_name("zbar_image_set_size")
func zbar_image_set_size(_ image: UnsafeMutableRawPointer?, _ width: UInt32, _ height: UInt32)

@_silgen_name("zbar_scan_image")
func zbar_scan_image(_ scanner: UnsafeMutableRawPointer?, _ image: UnsafeMutableRawPointer?)
    -> Int32

@_silgen_name("zbar_image_first_symbol")
func zbar_image_first_symbol(_ image: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?

@_silgen_name("zbar_symbol_get_type")
func zbar_symbol_get_type(_ symbol: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("zbar_symbol_get_data")
func zbar_symbol_get_data(_ symbol: UnsafeMutableRawPointer?) -> UnsafePointer<Int8>?

@_silgen_name("zbar_symbol_next")
func zbar_symbol_next(_ symbol: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?

// MARK: - ZBar Constants
let ZBAR_QRCODE: Int32 = 64
let ZBAR_CFG_ENABLE: Int32 = 1
let ZBAR_CFG_POSITION: Int32 = 2
let ZBAR_CFG_UNCERTAINTY: Int32 = 0x3030_3855

// ZBar image format constants
let ZBAR_FMT_Y800: Int32 = 0x3030_3859  // "Y800" (グレースケール)

let readingFrequencyLimit: TimeInterval = 0.5

// MARK: - QCQRCodeReaderDelegate Protocol
protocol QCQRCodeReaderDelegate: AnyObject {
    func didDetectQRCode(_ code: String)
    func didFailToReadQRCode(_ error: Error)
}

// MARK: - QCQRCodeReader Class
class QCQRCodeReader: NSObject {
    // MARK: - Properties
    weak var delegate: QCQRCodeReaderDelegate?
    private var isReading = true
    private var readString: String?

    // MARK: - Public Methods
    private var isReadingInProgress: Bool = false

    func startReading(from sampleBuffer: CMSampleBuffer) {
        guard !isReadingInProgress else { return }
        isReadingInProgress = true

        DispatchQueue.global().asyncAfter(deadline: .now() + readingFrequencyLimit) { [weak self] in
            self?.isReadingInProgress = false
        }

        isReading = true

        // Extract image from sample buffer
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            isReading = false
            return
        }

        // Convert to CIImage
        let ciImage = CIImage(cvImageBuffer: imageBuffer)

        // Convert to CGImage
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            isReading = false
            return
        }

        // Detect QR codes with ZBar
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.scanImageWithZBar(cgImage)

            DispatchQueue.main.async {
                self?.isReading = false

                // Register void string if scan is failed
                guard let code = result else {
                    self?.readString = ""
                    return
                }

                // Avoid duplicate reads
                if code == self?.readString || code.isEmpty {
                    return
                }
                self?.readString = code
                self?.delegate?.didDetectQRCode(code)
            }
        }
    }

    // MARK: - Private Methods
    private func scanImageWithZBar(_ image: CGImage) -> String? {
        let width = image.width
        let height = image.height

        // Convert image to grayscale and improve contrast
        let processedImage = preprocessImageForQRCode(image)

        // Create ZBar scanner safely
        guard let scanner = zbar_image_scanner_create() else {
            return nil
        }

        // Use defer to ensure resource cleanup
        defer {
            zbar_image_scanner_destroy(scanner)
        }

        // Configure scanner
        _ = zbar_image_scanner_set_config(scanner, 0, ZBAR_CFG_ENABLE, 1)
        _ = zbar_image_scanner_set_config(scanner, ZBAR_QRCODE, ZBAR_CFG_ENABLE, 1)
        _ = zbar_image_scanner_set_config(scanner, ZBAR_QRCODE, ZBAR_CFG_POSITION, 1)

        // Create zbar_image_t
        guard let zbarImage = zbar_image_create() else {
            return nil
        }

        // Manage zbar_image_t cleanup with defer
        defer {
            zbar_image_destroy(zbarImage)
        }

        // Get and convert image data
        guard let dataProvider = processedImage.dataProvider,
            let data = dataProvider.data
        else {
            return nil
        }

        let bytes = CFDataGetBytePtr(data)
        let length = CFDataGetLength(data)

        // Check data length
        guard length > 0 && bytes != nil else {
            return nil
        }

        // Set image data format (grayscale)
        let format: Int32 = ZBAR_FMT_Y800

        // Set data to zbar_image_t
        zbar_image_set_size(zbarImage, UInt32(width), UInt32(height))
        zbar_image_set_format(zbarImage, format)
        zbar_image_set_data(zbarImage, bytes, length, 0)

        let scanResult = zbar_scan_image(scanner, zbarImage)
        _ = zbar_image_scanner_set_config(scanner, ZBAR_QRCODE, ZBAR_CFG_UNCERTAINTY, 0)  // Disable uncertainty for faster processing

        var detectedCode: String? = nil

        if scanResult >= 0 {
            // Get results
            var symbol = zbar_image_first_symbol(zbarImage)

            while symbol != nil {
                let type = zbar_symbol_get_type(symbol)

                if type == ZBAR_QRCODE {
                    let symbolData = zbar_symbol_get_data(symbol)
                    if let symbolData = symbolData {
                        let code = String(cString: symbolData)
                        detectedCode = code
                        break
                    }
                }
                symbol = zbar_symbol_next(symbol)
            }
        }

        return detectedCode
    }

    private func preprocessImageForQRCode(_ image: CGImage) -> CGImage {
        let ciImage = CIImage(cgImage: image)

        // Combine all filters into one pipeline
        let combinedFilters = CIFilter(name: "CIColorControls")
        combinedFilters?.setValue(ciImage, forKey: kCIInputImageKey)
        combinedFilters?.setValue(0.0, forKey: kCIInputSaturationKey)  // Grayscale
        combinedFilters?.setValue(1.3, forKey: kCIInputContrastKey)  // Contrast Adjustment

        let sharpenFilter = CIFilter(name: "CISharpenLuminance")
        sharpenFilter?.setValue(combinedFilters?.outputImage, forKey: kCIInputImageKey)
        sharpenFilter?.setValue(0.5, forKey: kCIInputSharpnessKey)  // Sharpen Adjustment

        guard let processedImage = sharpenFilter?.outputImage,
            let cgImage = CIContext().createCGImage(processedImage, from: processedImage.extent)
        else {
            return image
        }

        // If alpha info remains, ensure conversion to grayscale
        if cgImage.alphaInfo != .none {
            let colorSpace = CGColorSpaceCreateDeviceGray()
            let bitmapInfo = CGImageAlphaInfo.none.rawValue

            guard
                let context = CGContext(
                    data: nil,
                    width: cgImage.width,
                    height: cgImage.height,
                    bitsPerComponent: 8,
                    bytesPerRow: cgImage.width,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo)
            else {
                return image
            }

            context.draw(
                cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            guard let newCGImage = context.makeImage() else {
                return image
            }
            return newCGImage
        }
        return cgImage
    }

    func stopReading() {
        isReading = false
    }
}
