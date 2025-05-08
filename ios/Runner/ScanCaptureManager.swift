import UIKit
import ARKit
import os.log

protocol ScanCaptureManagerDelegate: AnyObject {
    func scanCaptureManagerReachedStorageLimit(_ manager: ScanCaptureManager)
    func scanCaptureManager(_ manager: ScanCaptureManager, didUpdateStatus status: String)
}

class ScanCaptureManager {
    private let fileManager = FileManager.default
    private let captureFolderURL: URL
    private var imageIndex: Int = 0
    private var optimalFrameInterval: Int = 10
    private let minMovementDistance: Float = 0.05
    private var lastCameraPosition: SIMD3<Float>?
    private var lastQualityScore: Float = 0.5
    private var lastCaptureTime: TimeInterval = 0
    
    private let logger = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "com.your.app",
        category: "ScanCapture"
    )
    
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
        guard shouldCapture(frame: frame) else { return }
        
        if let processedImage = preprocessImage(frame.capturedImage) {
            saveProcessedImage(processedImage, frame: frame)
            saveCameraTransform(transform: frame.camera.transform, frame: frame)
            imageIndex += 1
            
            if imageIndex % 10 == 0 {
                ensureStorageLimit()
            }
        }
    }

    private func shouldCapture(frame: ARFrame) -> Bool {
        // Check minimum time interval
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastCaptureTime > Double(optimalFrameInterval)/30.0 else {
            return false
        }
        
        // Check movement sufficient
        let currentPosition = frame.camera.transform.columns.3.xyz
        if let lastPosition = lastCameraPosition {
            let distance = simd_distance(currentPosition, lastPosition)
            guard distance >= minMovementDistance else {
                delegate?.scanCaptureManager(self, didUpdateStatus: "Skipping - insufficient movement")
                return false
            }
        }
        
        // Check lighting conditions
        let avgBrightness = frame.lightEstimate?.ambientIntensity ?? 1000
        guard (300...2000).contains(avgBrightness) else {
            delegate?.scanCaptureManager(self, didUpdateStatus: "Skipping - poor lighting")
            return false
        }
        
        // Check motion blur
        if let motion = frame.camera.trackingState.motionBlurEstimate, motion > 0.1 {
            delegate?.scanCaptureManager(self, didUpdateStatus: "Skipping - motion blur detected")
            return false
        }
        
        // Check quality score
        let qualityScore = calculateQualityScore(frame: frame)
        adjustCaptureRate(qualityScore: qualityScore)
        
        lastCameraPosition = currentPosition
        lastCaptureTime = currentTime
        return true
    }
    
    private func calculateQualityScore(frame: ARFrame) -> Float {
            var score: Float = 0
            
            // Tracking quality
            switch frame.camera.trackingState {
            case .normal: score += 0.4
            case .limited: score += 0.2
            default: score += 0
            }
            
            // Feature point count
            if let rawFeaturePoints = frame.rawFeaturePoints {
                let featureDensity = Float(rawFeaturePoints.points.count) / 1000.0 // Fixed: Added .0 for Float conversion
                score += min(featureDensity, 0.3)
            }
            
            // Lighting
            if let lightEstimate = frame.lightEstimate {
                let normalizedLight = Float((lightEstimate.ambientIntensity - 300) / 1700.0) // Fixed: Explicit Float conversion
                score += min(max(normalizedLight, 0), 0.3)
            }
            
            return score
        }
    
    private func adjustCaptureRate(qualityScore: Float) {
        let baseInterval = 10
        let qualityDelta = qualityScore - lastQualityScore
        
        if qualityDelta < -0.2 {
            optimalFrameInterval = max(baseInterval / 2, 5)
            delegate?.scanCaptureManager(self, didUpdateStatus: "Increased capture rate - quality dropped")
        } else if qualityDelta > 0.2 {
            optimalFrameInterval = min(baseInterval * 2, 30)
            delegate?.scanCaptureManager(self, didUpdateStatus: "Decreased capture rate - quality improved")
        }
        
        lastQualityScore = qualityScore
    }

    private func preprocessImage(_ pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Auto-enhance
        let filters = ciImage.autoAdjustmentFilters(options: [.enhance: true])
        var processedImage = ciImage
        for filter in filters {
            filter.setValue(processedImage, forKey: kCIInputImageKey)
            processedImage = filter.outputImage ?? processedImage
        }
        
        // Local contrast enhancement
        let context = CIContext()
        guard let cgImage = context.createCGImage(processedImage, from: processedImage.extent) else {
            delegate?.scanCaptureManager(self, didUpdateStatus: "Failed to process image")
            return nil
        }
        
        return cgImage
    }
    
    private func saveProcessedImage(_ cgImage: CGImage, frame: ARFrame) {
        let uiImage = UIImage(cgImage: cgImage)
        let imageURL = captureFolderURL.appendingPathComponent("image_\(imageIndex).jpg")
        
        if let jpegData = uiImage.jpegData(compressionQuality: 0.9) {
            do {
                try jpegData.write(to: imageURL)
                currentStorageSize += Int64(jpegData.count)
                
                // Debug: Save feature visualization
                if imageIndex % 20 == 0 {
                    let debugImage = debugVisualizeFeatures(image: uiImage)
                    let debugURL = captureFolderURL.appendingPathComponent("debug_\(imageIndex).jpg")
                    try debugImage.jpegData(compressionQuality: 0.8)?.write(to: debugURL)
                }
            } catch {
                os_log("Failed to save image: %@", log: logger, type: .error, error.localizedDescription)
            }
        }
    }
    
    private func debugVisualizeFeatures(image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }
        
        // Replace SIFT with Vision framework feature detection
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(ciImage: ciImage)
        
        UIGraphicsBeginImageContext(image.size)
        image.draw(at: .zero)
        
        do {
            try handler.perform([request])
            if let results = request.results {
                for observation in results {
                    let boundingBox = observation.boundingBox
                    let rect = VNImageRectForNormalizedRect(boundingBox,
                                                          Int(image.size.width),
                                                          Int(image.size.height))
                    let path = UIBezierPath(rect: rect)
                    UIColor.red.setStroke()
                    path.stroke()
                }
            }
        } catch {
            print("Feature detection error: \(error)")
        }
        
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result ?? image
    }


    private func saveCameraTransform(transform: simd_float4x4, frame: ARFrame) {
        let confidence: Float
        switch frame.worldMappingStatus {
        case .mapped: confidence = 1.0
        case .extending: confidence = 0.8
        case .limited: confidence = 0.5
        case .notAvailable: confidence = 0.2
        @unknown default: confidence = 0.5
        }
        
        let poseData: [String: Any] = [
            "transform": transform.toArray(),
            "confidence": confidence,
            "timestamp": CACurrentMediaTime(),
            "light_estimate": frame.lightEstimate?.ambientIntensity ?? 0,
            "tracking_state": frame.camera.trackingState.description,
            "feature_count": frame.rawFeaturePoints?.points.count ?? 0
        ]
        
        let poseURL = captureFolderURL.appendingPathComponent("image_\(imageIndex)_pose.json")
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: poseData, options: [.prettyPrinted])
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
            lastCaptureTime = 0
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

extension simd_float4 {
    var xyz: SIMD3<Float> {
        return SIMD3<Float>(x, y, z)
    }
}

extension ARCamera.TrackingState {
    var motionBlurEstimate: Float? {
        guard case .limited(let reason) = self else { return nil }
        if reason == .excessiveMotion { return 1.0 }
        return nil
    }
}
