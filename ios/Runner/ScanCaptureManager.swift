import UIKit
import ARKit
import os.log

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
    
    // For automatic size management
    private let maxStorageMB: Int = 100  // Adjust based on your needs
    private var currentStorageSize: Int64 = 0

    init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        captureFolderURL = docs.appendingPathComponent("ScanCapture")
        
        // Clear previous scans and create fresh directory
        cleanupCaptureDirectory()
        createCaptureDirectory()
        
        os_log("Capture folder initialized at: %@", log: logger, type: .info, captureFolderURL.path)
    }

    // MARK: - Capture Methods
    func tryCapture(frame: ARFrame) {
        frameCount += 1
        guard frameCount % saveEveryNFrames == 0 else { return }

        os_log("Capturing frame %d", log: logger, type: .info, imageIndex)
        saveImage(frame: frame)
        saveCameraTransform(transform: frame.camera.transform)
        imageIndex += 1
        
        // Periodically check storage usage
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
        
        if let jpegData = uiImage.jpegData(compressionQuality: 0.85) {  // Slightly reduced quality for size
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
    
    // MARK: - File Management
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
    
    func deleteCaptureFiles(for indices: [Int]) {
        indices.forEach { index in
            let imageURL = captureFolderURL.appendingPathComponent("image_\(index).jpg")
            let poseURL = captureFolderURL.appendingPathComponent("image_\(index)_pose.json")
            
            [imageURL, poseURL].forEach { url in
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: url.path)
                    let fileSize = attributes[.size] as? Int64 ?? 0
                    try fileManager.removeItem(at: url)
                    currentStorageSize -= fileSize
                } catch {
                    os_log("Failed to delete file %@: %@",
                          log: logger, type: .error,
                          url.lastPathComponent, error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: - Storage Management
    func getCaptureCount() -> Int {
        do {
            let files = try fileManager.contentsOfDirectory(atPath: captureFolderURL.path)
            return files.filter { $0.hasSuffix(".jpg") }.count
        } catch {
            os_log("Failed to get capture count: %@", log: logger, type: .error, error.localizedDescription)
            return 0
        }
    }
    
    func currentDirectorySize() -> Int64 {
        return currentStorageSize
    }
    
    private func ensureStorageLimit() {
        let maxBytes = Int64(maxStorageMB) * 1_048_576
        guard currentStorageSize > maxBytes else { return }
        
        os_log("Storage limit reached (%lld bytes), cleaning oldest files",
              log: logger, type: .info, currentStorageSize)
        
        do {
            let files = try fileManager.contentsOfDirectory(at: captureFolderURL,
                                                         includingPropertiesForKeys: [.creationDateKey],
                                                         options: .skipsHiddenFiles)
            
            let sortedFiles = try files.sorted {
                let date1 = try $0.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                let date2 = try $1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                return date1 < date2
            }
            
            // Delete oldest files until under limit
            for file in sortedFiles {
                guard currentStorageSize > maxBytes else { break }
                
                let attributes = try fileManager.attributesOfItem(atPath: file.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                try fileManager.removeItem(at: file)
                currentStorageSize -= fileSize
                
                os_log("Deleted old file: %@", log: logger, type: .info, file.lastPathComponent)
            }
        } catch {
            os_log("Error managing storage: %@", log: logger, type: .error, error.localizedDescription)
        }
    }
}
