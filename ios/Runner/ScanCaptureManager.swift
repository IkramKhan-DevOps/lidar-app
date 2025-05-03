import UIKit
import ARKit
import os.log

protocol ScanCaptureManagerDelegate: AnyObject {
    func scanCaptureManagerReachedStorageLimit(_ manager: ScanCaptureManager)
}

class ScanCaptureManager {
    private let fileManager = FileManager.default
    private let captureFolderURL: URL
    private var imageIndex: Int = 0
    private let saveEveryNFrames: Int = 20
    private var frameCount: Int = 0
    private let logger = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "com.your.app",
        category: "ScanCapture"
    )
    
    // Updated to 500MB
    private let maxStorageMB: Int = 500
    private var currentStorageSize: Int64 = 0
    
    weak var delegate: ScanCaptureManagerDelegate?

    init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        captureFolderURL = docs.appendingPathComponent("ScanCapture")
        cleanupCaptureDirectory()
        createCaptureDirectory()
    }

    func tryCapture(frame: ARFrame) {
        frameCount += 1
        guard frameCount % saveEveryNFrames == 0 else { return }
        
        os_log("Capturing frame %d", log: logger, type: .info, imageIndex)
        saveImage(frame: frame)
        saveCameraTransform(transform: frame.camera.transform)
        imageIndex += 1
        
        if imageIndex % 10 == 0 {
            ensureStorageLimit()
        }
    }

    private func saveImage(frame: ARFrame) {
        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            os_log("Failed to create CGImage from pixel buffer", log: logger, type: .error)
            return
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        let imageURL = captureFolderURL.appendingPathComponent("image_\(imageIndex).jpg")
        
        if let jpegData = uiImage.jpegData(compressionQuality: 0.85) {
            do {
                try jpegData.write(to: imageURL)
                currentStorageSize += Int64(jpegData.count)
            } catch {
                os_log("Failed to save image: %@", log: logger, type: .error, error.localizedDescription)
            }
        }
    }

    private func saveCameraTransform(transform: simd_float4x4) {
        let transformArray = transform.toArray()
        let poseURL = captureFolderURL.appendingPathComponent("image_\(imageIndex)_pose.json")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: transformArray, options: [])
            try jsonData.write(to: poseURL)
            currentStorageSize += Int64(jsonData.count)
        } catch {
            os_log("Failed to save camera transform: %@", log: logger, type: .error, error.localizedDescription)
        }
    }

    private func createCaptureDirectory() {
        do {
            try fileManager.createDirectory(at: captureFolderURL,
                                         withIntermediateDirectories: true,
                                         attributes: nil)
        } catch {
            os_log("Failed to create capture directory: %@", log: logger, type: .error, error.localizedDescription)
        }
    }

    func cleanupCaptureDirectory() {
        do {
            let files = try fileManager.contentsOfDirectory(at: captureFolderURL,
                                                         includingPropertiesForKeys: nil)
            for file in files {
                try fileManager.removeItem(at: file)
            }
            currentStorageSize = 0
            imageIndex = 0
            frameCount = 0
            os_log("Cleaned up capture directory", log: logger, type: .info)
        } catch {
            os_log("Error cleaning capture directory: %@", log: logger, type: .error, error.localizedDescription)
        }
    }

    private func ensureStorageLimit() {
        let maxBytes = Int64(maxStorageMB) * 1_048_576
        guard currentStorageSize > maxBytes else { return }
        
        DispatchQueue.main.async {
            self.delegate?.scanCaptureManagerReachedStorageLimit(self)
        }
    }
}
