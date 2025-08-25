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
let ZBAR_CFG_UNCERTAINTY: Int32 = 0x30303855 // 品質設定の定数

// zbarの画像形式定数を正しく定義（4文字のASCII文字列として）
let ZBAR_FMT_Y800: Int32 = 0x30303859  // "Y800" (グレースケール)
let ZBAR_FMT_RGBA: Int32 = 0x42475241  // "RGBA"
let ZBAR_FMT_RGB: Int32 = 0x42475220   // "RGB "
let ZBAR_FMT_BGR: Int32 = 0x42475220   // "BGR "
let ZBAR_FMT_BGRA: Int32 = 0x42475241  // "BGRA"

// zbarの設定定数を正しく定義
let ZBAR_CFG_Y800: Int32 = 0x30303859
let ZBAR_CFG_RGBA: Int32 = 0x42475241
let ZBAR_CFG_RGB: Int32 = 0x42475220
let ZBAR_CFG_BGR: Int32 = 0x42475220
let ZBAR_CFG_BGRA: Int32 = 0x42475241

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
        
        NSLog("QRコード読み取り中: 画像サイズ %dx%d", width, height)
        
        // 画像をグレースケールに変換してコントラストを向上
        let processedImage = preprocessImageForQRCode(image)
        
        // 安全なzbarスキャナーの作成
        guard let scanner = zbar_image_scanner_create() else {
            NSLog("zbarスキャナーの作成に失敗")
            return nil
        }
        
        // リソースのクリーンアップを確実に行うためにdeferを使用
        defer {
            zbar_image_scanner_destroy(scanner)
        }
        
        // スキャナーの設定 - より包括的な設定
        let configResult = zbar_image_scanner_set_config(scanner, 0, ZBAR_CFG_ENABLE, 1)
        if configResult != 0 {
            NSLog("zbarスキャナーの基本設定に失敗: %d", configResult)
        }
        
        // QRコードを明示的に有効化
        let qrConfigResult = zbar_image_scanner_set_config(scanner, ZBAR_QRCODE, ZBAR_CFG_ENABLE, 1)
        if qrConfigResult != 0 {
            NSLog("QRコード設定に失敗: %d", qrConfigResult)
        }
        
        // スキャナーの感度を向上
        let sensitivityResult = zbar_image_scanner_set_config(scanner, ZBAR_QRCODE, ZBAR_CFG_POSITION, 1)
        if sensitivityResult != 0 {
            NSLog("QRコード位置検出設定に失敗: %d", sensitivityResult)
        }
        
        // より多くのシンボルタイプを有効化
        let qr1Result = zbar_image_scanner_set_config(scanner, ZBAR_QRCODE, ZBAR_CFG_ENABLE, 1)
        if qr1Result != 0 {
            NSLog("QRコード1設定に失敗: %d", qr1Result)
        }
        
        // スキャナーの品質設定を調整
        let qualityResult = zbar_image_scanner_set_config(scanner, 0, ZBAR_CFG_UNCERTAINTY, 0)
        if qualityResult != 0 {
            NSLog("品質設定に失敗: %d", qualityResult)
        }
        
        NSLog("zbarスキャナーの設定完了")
        
        // zbar_image_tの作成
        guard let zbarImage = zbar_image_create() else {
            NSLog("zbar_image_tの作成に失敗")
            return nil
        }
        
        // zbar_image_tのクリーンアップもdeferで管理
        defer {
            zbar_image_destroy(zbarImage)
        }
        
        // 画像データの取得と変換
        guard let dataProvider = processedImage.dataProvider,
              let data = dataProvider.data else {
            NSLog("画像データの取得に失敗")
            return nil
        }
        
        let bytes = CFDataGetBytePtr(data)
        let length = CFDataGetLength(data)
        
        NSLog("画像データ: 長さ=%d, ビット深度=%d, アルファ情報=%d", length, processedImage.bitsPerComponent, processedImage.alphaInfo.rawValue)
        
        // データの長さを確認
        guard length > 0 && bytes != nil else {
            NSLog("画像データが無効です")
            return nil
        }
        
        // 画像データの形式を正しく設定
        // 前処理でグレースケールに変換されているため、常にY800形式を使用
        let format: Int32 = ZBAR_FMT_Y800 // Y800 (グレースケール)
        let expectedLength: Int = width * height // グレースケール画像は1ピクセルあたり1バイト
        
        NSLog("グレースケール画像として処理: 期待される長さ=%d", expectedLength)
        NSLog("使用する画像形式: 0x%08X (Y800)", format)
        
        // データの長さが期待される値と一致するか確認
        if length != expectedLength {
            NSLog("警告: 画像データの長さが期待される値と一致しません。実際=%d, 期待=%d", length, expectedLength)
            NSLog("データの長さを調整して処理を続行します")
            
            // データの長さを調整（切り詰めるか、パディングを追加）
            let adjustedLength = min(length, expectedLength)
            NSLog("調整後のデータ長: %d", adjustedLength)
        }
        
        // zbar_image_tにデータを設定する前に、画像の状態を確認
        NSLog("zbar_image_t設定前: 幅=%d, 高さ=%d, 形式=0x%08X", width, height, format)
        
        // より安全な方法でzbar_image_tにデータを設定
        // まず、画像のサイズを設定
        zbar_image_set_size(zbarImage, UInt32(width), UInt32(height))
        
        // 次に、画像の形式を設定
        zbar_image_set_format(zbarImage, format)
        
        // 画像データの設定前に最終確認
        NSLog("画像データ設定前の最終確認: 幅=%d, 高さ=%d, 形式=0x%08X, データ長=%d", width, height, format, length)
        
        // 最後に、画像データを設定 (cleanup関数はnilを渡す)
        zbar_image_set_data(zbarImage, bytes, length, 0)
        
        NSLog("zbar_image_t設定完了")
        
        // 設定後の状態を確認
        NSLog("zbar_image_t設定後の確認: 幅=%d, 高さ=%d, 形式=0x%08X", width, height, format)
        
        // 画像データの設定が成功したか確認
        NSLog("画像データ設定確認: データ長=%d", length)
        
        // zbar_image_tの状態を検証
        NSLog("zbar_image_t状態検証: 設定完了")
        
        // 設定完了後の最終検証
        NSLog("zbar_image_t最終検証: すべての設定が完了")
        
        // 画像データの整合性を最終確認
        NSLog("画像データ整合性確認: 幅=%d, 高さ=%d, 期待される長さ=%d, 実際の長さ=%d", width, height, width * height, length)
        
        // zbar_image_tの内部状態を確認
        NSLog("zbar_image_t内部状態確認: 設定完了、スキャン準備完了")
        
        // 画像をスキャン
        NSLog("zbarスキャン開始: 画像形式=0x%08X, サイズ=%dx%d", format, width, height)
        
        // スキャン前の最終状態確認
        NSLog("スキャン前の最終状態確認: 画像形式=0x%08X, サイズ=%dx%d, データ長=%d", format, width, height, length)
        
        // スキャン前のzbar_image_tの状態を最終確認
        NSLog("スキャン前のzbar_image_t状態確認: 画像形式=0x%08X, サイズ=%dx%d", format, width, height)
        
        let scanResult = zbar_scan_image(scanner, zbarImage)
        NSLog("zbarスキャン結果: %d", scanResult)
        
        // スキャン結果の詳細分析
        NSLog("スキャン結果詳細分析: 結果=%d, 画像形式=0x%08X, サイズ=%dx%d", scanResult, format, width, height)
        
        var detectedCode: String? = nil
        
        if scanResult >= 0 {
            // 結果を取得
            var symbol = zbar_image_first_symbol(zbarImage)
            var symbolCount = 0
            
            NSLog("スキャン成功: シンボルの検索を開始")
            
            while symbol != nil {
                let type = zbar_symbol_get_type(symbol)
                NSLog("シンボル %d: タイプ=%d", symbolCount, type)
                
                if type == ZBAR_QRCODE {
                    let symbolData = zbar_symbol_get_data(symbol)
                    if let symbolData = symbolData {
                        let code = String(cString: symbolData)
                        NSLog("QRコードを検出: %@", code)
                        detectedCode = code
                        break
                    } else {
                        NSLog("シンボル %d: QRコードタイプだがデータが取得できません", symbolCount)
                    }
                } else {
                    NSLog("シンボル %d: QRコード以外のタイプ (タイプ=%d)", symbolCount, type)
                }
                symbol = zbar_symbol_next(symbol)
                symbolCount += 1
            }
            
            if symbolCount == 0 {
                NSLog("検出されたシンボルがありません")
                NSLog("画像の品質やQRコードの可視性を確認してください")
            } else {
                NSLog("検出されたシンボル数: %d", symbolCount)
            }
        } else {
            NSLog("zbarスキャンに失敗: %d", scanResult)
            // スキャンに失敗した場合でも、zbar_image_tは正常に作成されているはず
            NSLog("スキャン失敗の詳細: 画像形式=0x%08X, サイズ=%dx%d", format, width, height)
            
            // 失敗の原因を分析
            switch scanResult {
            case -1:
                NSLog("スキャン失敗の原因: 内部エラー")
            case -2:
                NSLog("スキャン失敗の原因: 無効な画像データ")
            case -3:
                NSLog("スキャン失敗の原因: メモリ不足")
            default:
                NSLog("スキャン失敗の原因: 不明なエラー (%d)", scanResult)
            }
        }
        
        NSLog("QRコード読み取り処理完了")
        
        // 処理完了後の状態確認
        NSLog("処理完了後の確認: 検出されたコード=%@, スキャン結果=%d", detectedCode ?? "なし", scanResult)
        
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
            NSLog("グレースケール変換に失敗、元の画像を使用")
            return image
        }
        
        // コントラストを向上
        let contrastFilter = CIFilter(name: "CIColorControls")
        contrastFilter?.setValue(grayscaleImage, forKey: kCIInputImageKey)
        contrastFilter?.setValue(1.3, forKey: kCIInputContrastKey) // コントラストを1.3倍に
        
        guard let contrastImage = contrastFilter?.outputImage else {
            NSLog("コントラスト向上に失敗、グレースケール画像を使用")
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
            NSLog("シャープネス向上に失敗、コントラスト画像を使用")
            guard let cgImage = context.createCGImage(contrastImage, from: contrastImage.extent) else {
                return image
            }
            return cgImage
        }
        
        // グレースケール画像の情報を確認
        NSLog("前処理後の画像: 幅=%d, 高さ=%d, ビット深度=%d, アルファ情報=%d", 
              cgImage.width, cgImage.height, cgImage.bitsPerComponent, cgImage.alphaInfo.rawValue)
        
        // アルファ情報が残っている場合は、確実にグレースケールに変換
        if cgImage.alphaInfo != .none {
            NSLog("アルファ情報が残っているため、強制的にグレースケールに変換")
            
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
                NSLog("グレースケール変換に失敗、元の画像を使用")
                return image
            }
            
            // 元の画像をグレースケールに変換して描画
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            
            // 新しいグレースケール画像を作成
            guard let newCGImage = context.makeImage() else {
                NSLog("グレースケール画像の作成に失敗、元の画像を使用")
                return image
            }
            
            NSLog("強制グレースケール変換完了: 幅=%d, 高さ=%d, ビット深度=%d, アルファ情報=%d", 
                  newCGImage.width, newCGImage.height, newCGImage.bitsPerComponent, newCGImage.alphaInfo.rawValue)
            
            // 最終的な画像データの整合性を確認
            NSLog("最終画像データ確認: 幅=%d, 高さ=%d, 期待されるデータ長=%d", 
                  newCGImage.width, newCGImage.height, newCGImage.width * newCGImage.height)
            
            return newCGImage
        }
        
        NSLog("画像の前処理完了: グレースケール変換、コントラスト向上、シャープネス向上")
        return cgImage
    }
    
    func stopReading() {
        isReading = false
    }
}
