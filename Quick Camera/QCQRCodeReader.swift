import Foundation
import AVFoundation
import CoreImage

// zbarのC関数を直接宣言
@_silgen_name("zbar_image_scanner_create")
func zbar_image_scanner_create() -> UnsafeMutableRawPointer?

@_silgen_name("zbar_image_scanner_destroy")
func zbar_image_scanner_destroy(_ scanner: UnsafeMutableRawPointer?)

@_silgen_name("zbar_image_scanner_set_config")
func zbar_image_scanner_set_config(_ scanner: UnsafeMutableRawPointer?, _ symbology: Int32, _ config: Int32, _ value: Int32) -> Int32

@_silgen_name("zbar_image_create")
func zbar_image_create() -> UnsafeMutableRawPointer?

@_silgen_name("zbar_image_destroy")
func zbar_image_destroy(_ image: UnsafeMutableRawPointer?)

@_silgen_name("zbar_image_set_data")
func zbar_image_set_data(_ image: UnsafeMutableRawPointer?, _ data: UnsafePointer<UInt8>?, _ length: Int, _ format: Int32)

@_silgen_name("zbar_image_set_format")
func zbar_image_set_format(_ image: UnsafeMutableRawPointer?, _ format: Int32)

@_silgen_name("zbar_image_set_size")
func zbar_image_set_size(_ image: UnsafeMutableRawPointer?, _ width: UInt32, _ height: UInt32)

@_silgen_name("zbar_scan_image")
func zbar_scan_image(_ scanner: UnsafeMutableRawPointer?, _ image: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("zbar_image_first_symbol")
func zbar_image_first_symbol(_ image: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?

@_silgen_name("zbar_symbol_get_type")
func zbar_symbol_get_type(_ symbol: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("zbar_symbol_get_data")
func zbar_symbol_get_data(_ symbol: UnsafeMutableRawPointer?) -> UnsafePointer<Int8>?

@_silgen_name("zbar_symbol_next")
func zbar_symbol_next(_ symbol: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?

// zbarの定数を定義
let ZBAR_QRCODE: Int32 = 64
let ZBAR_CFG_ENABLE: Int32 = 1
let ZBAR_CFG_POSITION: Int32 = 2
let ZBAR_CFG_UNCERTAINTY: Int32 = 0x30303855

// zbarの画像形式定数
let ZBAR_FMT_Y800: Int32 = 0x30303859  // "Y800" (グレースケール)


protocol QCQRCodeReaderDelegate: AnyObject {
    func didDetectQRCode(_ code: String)
    func didFailToReadQRCode(_ error: Error)
}

class QCQRCodeReader: NSObject {
    weak var delegate: QCQRCodeReaderDelegate?
    private var isReading = false
    
    func startReading(from sampleBuffer: CMSampleBuffer) {
        guard !isReading else { return }
        
        isReading = true
        
        // サンプルバッファから画像を取得
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            isReading = false
            return
        }
        
        // CIImageに変換
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        
        // CGImageに変換
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            isReading = false
            return
        }
        
        // zbarでQRコードを検出
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.scanImageWithZBar(cgImage)
            
            DispatchQueue.main.async {
                self?.isReading = false
                
                if let code = result {
                    self?.delegate?.didDetectQRCode(code)
                }
                // QRコードが見つからない場合は何もしない（正常な動作）
            }
        }
    }
    
    private func scanImageWithZBar(_ image: CGImage) -> String? {
        let width = image.width
        let height = image.height
        
        // 画像をグレースケールに変換してコントラストを向上
        let processedImage = preprocessImageForQRCode(image)
        
        // 安全なzbarスキャナーの作成
        guard let scanner = zbar_image_scanner_create() else {
            return nil
        }
        
        // リソースのクリーンアップを確実に行うためにdeferを使用
        defer {
            zbar_image_scanner_destroy(scanner)
        }
        
        // スキャナーの設定
        zbar_image_scanner_set_config(scanner, 0, ZBAR_CFG_ENABLE, 1)
        zbar_image_scanner_set_config(scanner, ZBAR_QRCODE, ZBAR_CFG_ENABLE, 1)
        zbar_image_scanner_set_config(scanner, ZBAR_QRCODE, ZBAR_CFG_POSITION, 1)
        
        // zbar_image_tの作成
        guard let zbarImage = zbar_image_create() else {
            return nil
        }
        
        // zbar_image_tのクリーンアップもdeferで管理
        defer {
            zbar_image_destroy(zbarImage)
        }
        
        // 画像データの取得と変換
        guard let dataProvider = processedImage.dataProvider,
              let data = dataProvider.data else {
            return nil
        }
        
        let bytes = CFDataGetBytePtr(data)
        let length = CFDataGetLength(data)
        
        // データの長さを確認
        guard length > 0 && bytes != nil else {
            return nil
        }
        
        // 画像データの形式を設定（グレースケール）
        let format: Int32 = ZBAR_FMT_Y800
        
        // zbar_image_tにデータを設定
        zbar_image_set_size(zbarImage, UInt32(width), UInt32(height))
        zbar_image_set_format(zbarImage, format)
        zbar_image_set_data(zbarImage, bytes, length, 0)
        
        let scanResult = zbar_scan_image(scanner, zbarImage)
        
        var detectedCode: String? = nil
        
        if scanResult >= 0 {
            // 結果を取得
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
        let context = CIContext()
        let ciImage = CIImage(cgImage: image)
        
        // 確実にグレースケール画像に変換
        let grayscaleFilter = CIFilter(name: "CIColorControls")
        grayscaleFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        grayscaleFilter?.setValue(0.0, forKey: kCIInputSaturationKey) // 彩度を0にしてグレースケール化
        
        guard let grayscaleImage = grayscaleFilter?.outputImage else {
            return image
        }
        
        // コントラストを向上
        let contrastFilter = CIFilter(name: "CIColorControls")
        contrastFilter?.setValue(grayscaleImage, forKey: kCIInputImageKey)
        contrastFilter?.setValue(1.3, forKey: kCIInputContrastKey) // コントラストを1.3倍に
        
        guard let contrastImage = contrastFilter?.outputImage else {
            guard let cgImage = context.createCGImage(grayscaleImage, from: grayscaleImage.extent) else {
                return image
            }
            return cgImage
        }
        
        // シャープネスを向上
        let sharpenFilter = CIFilter(name: "CISharpenLuminance")
        sharpenFilter?.setValue(contrastImage, forKey: kCIInputImageKey)
        sharpenFilter?.setValue(0.5, forKey: kCIInputSharpnessKey) // シャープネスを0.5に
        
        guard let finalImage = sharpenFilter?.outputImage,
              let cgImage = context.createCGImage(finalImage, from: finalImage.extent) else {
            guard let cgImage = context.createCGImage(contrastImage, from: contrastImage.extent) else {
                return image
            }
            return cgImage
        }
        
        
        // アルファ情報が残っている場合は、確実にグレースケールに変換
        if cgImage.alphaInfo != .none {
            
            // グレースケール画像を新しく作成
            let colorSpace = CGColorSpaceCreateDeviceGray()
            let bitmapInfo = CGImageAlphaInfo.none.rawValue
            
            guard let context = CGContext(data: nil,
                                        width: cgImage.width,
                                        height: cgImage.height,
                                        bitsPerComponent: 8,
                                        bytesPerRow: cgImage.width,
                                        space: colorSpace,
                                        bitmapInfo: bitmapInfo) else {
                return image
            }
            
            // 元の画像をグレースケールに変換して描画
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            
            // 新しいグレースケール画像を作成
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
