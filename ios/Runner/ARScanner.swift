import ARKit
import SceneKit
import Foundation
import os.log
import UIKit
import AVFoundation
import SSZipArchive
import Vision
import CoreLocation
import simd
import QuickLook

struct ScanMetadata: Codable {
    var name: String
    var timestamp: Date
    var scanID: String
    var coordinates: [[Double]]?
    var coordinateTimestamps: [Double]? // New field for timestamps of coordinates
    var locationName: String?
    var modelSizeBytes: Int64?
    var imageCount: Int
    var status: String
    var snapshotPath: String?
    var durationSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case name
        case timestamp
        case scanID = "scan_id"
        case coordinates
        case coordinateTimestamps = "coordinate_timestamps" // New coding key
        case locationName = "location_name"
        case modelSizeBytes = "model_size_bytes"
        case imageCount = "image_count"
        case status
        case snapshotPath = "snapshot_path"
        case durationSeconds = "duration_seconds"
    }
}

@available(iOS 13.0.0, *)
class ScanLocalStorage {
    static let shared = ScanLocalStorage()
    private let rootScanDir = "ARScans"
    private let fileManager = FileManager.default
    private let documentsURL: URL
    private let geocoder = CLGeocoder()

    private init() {
        guard let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Documents directory not found")
        }
        documentsURL = url
        createRootDirectory()
    }

    private func createRootDirectory() {
        var scansURL = documentsURL.appendingPathComponent(rootScanDir)
        do {
            try fileManager.createDirectory(at: scansURL, withIntermediateDirectories: true)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try scansURL.setResourceValues(resourceValues)
            os_log("Created root directory: %@", log: OSLog.default, type: .info, scansURL.path)
        } catch {
            os_log("Failed to create root directory: %@", log: OSLog.default, type: .error, error.localizedDescription)
        }
    }

    func getCustomFolderURL(folderName: String) -> URL? {
        var customFolderURL = documentsURL.appendingPathComponent(rootScanDir).appendingPathComponent(folderName)
        do {
            try fileManager.createDirectory(at: customFolderURL, withIntermediateDirectories: true)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try customFolderURL.setResourceValues(resourceValues)
            os_log("Created custom folder: %@", log: OSLog.default, type: .info, customFolderURL.path)
            return customFolderURL
        } catch {
            os_log("Failed to create custom folder: %@", log: OSLog.default, type: .error, error.localizedDescription)
            return nil
        }
    }

    func createTempScanFolder() -> URL? {
        let tempScanID = UUID().uuidString
        var tempFolderURL = documentsURL.appendingPathComponent(rootScanDir).appendingPathComponent("temp_\(tempScanID)")
        do {
            try fileManager.createDirectory(at: tempFolderURL, withIntermediateDirectories: true)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try tempFolderURL.setResourceValues(resourceValues)
            os_log("Created temporary scan folder: %@", log: OSLog.default, type: .info, tempFolderURL.path)
            return tempFolderURL
        } catch {
            os_log("Failed to create temporary scan folder: %@", log: OSLog.default, type: .error, error.localizedDescription)
            return nil
        }
    }

    func finalizeScanFolder(tempFolderURL: URL, name: String?, coordinates: [[Double]]? = nil, coordinateTimestamps: [Double]? = nil, imageCount: Int, durationSeconds: Double? = nil) async -> (url: URL?, metadata: ScanMetadata?) {
        let scanID = UUID().uuidString
        let timestamp = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let defaultName = "Scan_\(dateFormatter.string(from: timestamp))"
        let finalName = name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true ? defaultName : name!
        var finalFolderURL = documentsURL.appendingPathComponent(rootScanDir).appendingPathComponent(scanID)

        var zipSizeBytes: Int64?
        var usdzSizeBytes: Int64?
        let zipURL = tempFolderURL.appendingPathComponent("input_data.zip")
        let usdzURL = tempFolderURL.appendingPathComponent("model.usdz")
        if fileManager.fileExists(atPath: zipURL.path) {
            if let attributes = try? fileManager.attributesOfItem(atPath: zipURL.path),
               let size = attributes[.size] as? Int64 {
                zipSizeBytes = size
            }
        }
        if fileManager.fileExists(atPath: usdzURL.path) {
            if let attributes = try? fileManager.attributesOfItem(atPath: usdzURL.path),
               let size = attributes[.size] as? Int64 {
                usdzSizeBytes = size
            }
        }
        let modelSizeBytes = (zipSizeBytes ?? 0) + (usdzSizeBytes ?? 0)

        var locationName: String?
        if let lastCoordinate = coordinates?.last, !coordinates!.isEmpty {
            let location = CLLocation(latitude: lastCoordinate[0], longitude: lastCoordinate[1])
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                if let placemark = placemarks.first {
                    let components = [
                        placemark.locality,
                        placemark.administrativeArea,
                        placemark.country
                    ].compactMap { $0 }.joined(separator: ", ")
                    locationName = components.isEmpty ? "Unknown Location" : components
                }
            } catch {
                os_log("Reverse geocoding failed: %@", log: OSLog.default, type: .error, error.localizedDescription)
            }
        }

        do {
            try fileManager.createDirectory(at: finalFolderURL, withIntermediateDirectories: true)
            let contents = try fileManager.contentsOfDirectory(at: tempFolderURL, includingPropertiesForKeys: nil)
            for item in contents {
                let destination = finalFolderURL.appendingPathComponent(item.lastPathComponent)
                try fileManager.moveItem(at: item, to: destination)
            }

            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try finalFolderURL.setResourceValues(resourceValues)

            let metadata = ScanMetadata(
                name: finalName,
                timestamp: timestamp,
                scanID: scanID,
                coordinates: coordinates,
                coordinateTimestamps: coordinateTimestamps, // Include timestamps
                locationName: locationName,
                modelSizeBytes: modelSizeBytes,
                imageCount: imageCount,
                status: "pending",
                snapshotPath: nil,
                durationSeconds: durationSeconds
            )
            var metadataURL = finalFolderURL.appendingPathComponent("metadata.json")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let metadataData = try encoder.encode(metadata)
            try metadataData.write(to: metadataURL)
            try metadataURL.setResourceValues(resourceValues)

            try fileManager.removeItem(at: tempFolderURL)

            os_log("Finalized scan folder: %@", log: OSLog.default, type: .info, finalFolderURL.path)
            return (finalFolderURL, metadata)
        } catch {
            os_log("Failed to finalize scan folder: %@", log: OSLog.default, type: .error, error.localizedDescription)
            return (nil, nil)
        }
    }

    func updateScanName(_ name: String, for scanFolderURL: URL) -> Bool {
        var metadataURL = scanFolderURL.appendingPathComponent("metadata.json")
        do {
            let data = try Data(contentsOf: metadataURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var metadata = try decoder.decode(ScanMetadata.self, from: data)

            let sanitizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            metadata.name = sanitizedName.isEmpty ? metadata.name : sanitizedName

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let updatedData = try encoder.encode(metadata)
            try updatedData.write(to: metadataURL)

            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try metadataURL.setResourceValues(resourceValues)

            os_log("Updated scan name to '%@' for: %@", log: OSLog.default, type: .info, metadata.name, scanFolderURL.path)
            return true
        } catch {
            os_log("Failed to update scan name: %@", log: OSLog.default, type: .error, error.localizedDescription)
            return false
        }
    }

    func updateScanStatus(_ status: String, for scanFolderURL: URL) -> Bool {
        var metadataURL = scanFolderURL.appendingPathComponent("metadata.json")
        do {
            let data = try Data(contentsOf: metadataURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var metadata = try decoder.decode(ScanMetadata.self, from: data)

            metadata.status = status

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let updatedData = try encoder.encode(metadata)
            try updatedData.write(to: metadataURL)

            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try metadataURL.setResourceValues(resourceValues)

            os_log("Updated scan status to '%@' for: %@", log: OSLog.default, type: .info, status, scanFolderURL.path)
            return true
        } catch {
            os_log("Failed to update scan status: %@", log: OSLog.default, type: .error, error.localizedDescription)
            return false
        }
    }

    func saveInputZip(_ zipData: Data, to scanFolderURL: URL) -> URL? {
        var zipURL = scanFolderURL.appendingPathComponent("input_data.zip")
        do {
            try zipData.write(to: zipURL)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try zipURL.setResourceValues(resourceValues)
            os_log("Saved ZIP to: %@", log: OSLog.default, type: .info, zipURL.path)
            return zipURL
        } catch {
            os_log("Failed to save ZIP: %@", log: OSLog.default, type: .error, error.localizedDescription)
            return nil
        }
    }

    func saveUSDZModel(_ usdzData: Data, to scanFolderURL: URL) -> URL? {
        var usdzURL = scanFolderURL.appendingPathComponent("model.usdz")
        do {
            try usdzData.write(to: usdzURL)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try usdzURL.setResourceValues(resourceValues)
            os_log("Saved USDZ to: %@", log: OSLog.default, type: .info, usdzURL.path)
            return usdzURL
        } catch {
            os_log("Failed to save USDZ: %@", log: OSLog.default, type: .error, error.localizedDescription)
            return nil
        }
    }

    func getAllScans() -> [(url: URL, metadata: ScanMetadata?)] {
        let startTime = CFAbsoluteTimeGetCurrent()
        let scansURL = documentsURL.appendingPathComponent(rootScanDir)
        do {
            let folderURLs = try fileManager.contentsOfDirectory(
                at: scansURL,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )

            var scans: [(url: URL, metadata: ScanMetadata?)] = []
            for folderURL in folderURLs {
                let metadataURL = folderURL.appendingPathComponent("metadata.json")
                var metadata: ScanMetadata?

                var zipSizeBytes: Int64?
                var usdzSizeBytes: Int64?
                let zipURL = folderURL.appendingPathComponent("input_data.zip")
                let usdzURL = folderURL.appendingPathComponent("model.usdz")
                let snapshotURL = folderURL.appendingPathComponent("snapshot.png")
                if fileManager.fileExists(atPath: zipURL.path) {
                    if let attributes = try? fileManager.attributesOfItem(atPath: zipURL.path),
                       let size = attributes[.size] as? Int64 {
                        zipSizeBytes = size
                    }
                }
                if fileManager.fileExists(atPath: usdzURL.path) {
                    if let attributes = try? fileManager.attributesOfItem(atPath: usdzURL.path),
                       let size = attributes[.size] as? Int64 {
                        usdzSizeBytes = size
                    }
                }
                let totalSizeBytes = (zipSizeBytes ?? 0) + (usdzSizeBytes ?? 0)

                if fileManager.fileExists(atPath: metadataURL.path) {
                    do {
                        let data = try Data(contentsOf: metadataURL)
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        metadata = try decoder.decode(ScanMetadata.self, from: data)
                        metadata?.modelSizeBytes = totalSizeBytes
                        if fileManager.fileExists(atPath: snapshotURL.path) {
                            metadata?.snapshotPath = "snapshot.png"
                        }
                    } catch {
                        os_log("Failed to read metadata for %@: %@", log: OSLog.default, type: .error, folderURL.path, error.localizedDescription)
                        metadata = ScanMetadata(
                            name: folderURL.lastPathComponent,
                            timestamp: (try? folderURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date(),
                            scanID: folderURL.lastPathComponent,
                            coordinates: nil,
                            coordinateTimestamps: nil, // Initialize new field
                            locationName: nil,
                            modelSizeBytes: totalSizeBytes,
                            imageCount: 0,
                            status: "pending",
                            snapshotPath: fileManager.fileExists(atPath: snapshotURL.path) ? "snapshot.png" : nil,
                            durationSeconds: nil
                        )
                    }
                } else {
                    metadata = ScanMetadata(
                        name: folderURL.lastPathComponent,
                        timestamp: (try? folderURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date(),
                        scanID: folderURL.lastPathComponent,
                        coordinates: nil,
                        coordinateTimestamps: nil, // Initialize new field
                        locationName: nil,
                        modelSizeBytes: totalSizeBytes,
                        imageCount: 0,
                        status: "pending",
                        snapshotPath: fileManager.fileExists(atPath: snapshotURL.path) ? "snapshot.png" : nil,
                        durationSeconds: nil
                    )
                }

                scans.append((url: folderURL, metadata: metadata))
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            os_log("getAllScans took %f seconds", log: OSLog.default, type: .info, elapsed)
            return scans.sorted { ($0.metadata?.timestamp ?? Date()) > ($1.metadata?.timestamp ?? Date()) }
        } catch {
            os_log("Failed to list scans: %@", log: OSLog.default, type: .error, error.localizedDescription)
            return []
        }
    }

    func hasUSDZModel(in scanFolderURL: URL) -> Bool {
        let usdzURL = scanFolderURL.appendingPathComponent("model.usdz")
        return fileManager.fileExists(atPath: usdzURL.path)
    }

    func deleteScan(at scanFolderURL: URL) -> Bool {
        do {
            try fileManager.removeItem(at: scanFolderURL)
            os_log("Deleted scan folder: %@", log: OSLog.default, type: .info, scanFolderURL.path)
            return true
        } catch {
            os_log("Failed to delete scan folder: %@", log: OSLog.default, type: .error, error.localizedDescription)
            return false
        }
    }

    func getScanImages(folderPath: String) -> [String]? {
        let folderURL = URL(fileURLWithPath: folderPath)
        var tempDirURL = folderURL.appendingPathComponent("temp_images", isDirectory: true)
        let zipURL = folderURL.appendingPathComponent("input_data.zip")

        do {
            try fileManager.createDirectory(at: tempDirURL, withIntermediateDirectories: true, attributes: nil)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try tempDirURL.setResourceValues(resourceValues)

            guard fileManager.fileExists(atPath: zipURL.path) else {
                os_log("No input_data.zip found in folder: %@", log: OSLog.default, type: .error, folderPath)
                try? fileManager.removeItem(at: tempDirURL)
                return nil
            }

            let success = SSZipArchive.unzipFile(atPath: zipURL.path, toDestination: tempDirURL.path)
            guard success else {
                os_log("Failed to unzip file at: %@", log: OSLog.default, type: .error, zipURL.path)
                try? fileManager.removeItem(at: tempDirURL)
                return nil
            }

            let imagesDirURL = tempDirURL.appendingPathComponent("images")
            let contents = try fileManager.contentsOfDirectory(at: imagesDirURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            let imagePaths = contents
                .filter { $0.path.lowercased().hasSuffix(".jpg") && $0.path.contains("image_") }
                .map { $0.path }
            os_log("Extracted %d image_*.jpg files from zip in folder: %@, paths: %@", log: OSLog.default, type: .info, imagePaths.count, folderPath, imagePaths)

            return imagePaths.isEmpty ? nil : imagePaths
        } catch {
            os_log("Failed to extract images from zip for %@: %@", log: OSLog.default, type: .error, folderPath, error.localizedDescription)
            try? fileManager.removeItem(at: tempDirURL)
            return nil
        }
    }

    func openFolder(folderPath: String) -> String? {
        let folderURL = URL(fileURLWithPath: folderPath)
        if !fileManager.fileExists(atPath: folderURL.path) {
            os_log("Folder not found: %@", log: OSLog.default, type: .error, folderPath)
            return nil
        }
        os_log("Folder access requested: %@", log: OSLog.default, type: .info, folderPath)
        return "Folder access requested: \(folderPath)"
    }
}

// MARK: - ARScannerDelegate
@available(iOS 13.4, *)
protocol ARScannerDelegate: AnyObject {
    func arScanner(_ scanner: ARScanner, didUpdateStatus status: String)
    func arScanner(_ scanner: ARScanner, didUpdateMeshesCount count: Int)
    func arScannerDidStopScanning(_ scanner: ARScanner)
    func arScanner(_ scanner: ARScanner, showAlertWithTitle title: String, message: String)
    func arScanner(_ scanner: ARScanner, didCaptureDebugImage image: UIImage)
    func arScanner(_ scanner: ARScanner, promptForScanName completion: @escaping (String?) -> Void)
    func arScanner(_ scanner: ARScanner, didUpdateDuration duration: Double)
}

@available(iOS 13.4, *)
class ARScanner: NSObject {
    weak var delegate: ARScannerDelegate?
    private let arView = ARSCNView()
    private var allCapturedMeshes = [UUID: CapturedMesh]()
    private var meshNodes = [UUID: SCNNode]()
    private let meshProcessingQueue = DispatchQueue(label: "mesh.processing.queue", qos: .userInitiated)
    private let captureManager = ScanCaptureManager()
    private var lastMessageTime: Date = .distantPast
    private var lastMessage: String?
    private var lastSignificantMeshUpdate = Date()
    private var sceneBounds = BoundingBox()
    private var cameraPositions: [simd_float3] = []
    private var lastCameraPosition: simd_float3?
    private var coordinates: [[Double]] = []
    private var coordinateTimestamps: [Double] = [] // New array for timestamps
    private let locationManager = LocationManager()
    var currentScanFolderURL: URL?
    private var imageCount: Int = 0
    private var isProcessingFrames: Bool = true
    private var lastCompletionPercentage: Int?
    private var scanStartTime: Date?
    private var scanDuration: Double = 0.0
    private var lastCoordinateCaptureTime: TimeInterval = 0 // New property for time-based capture

    var view: ARSCNView { return arView }
    var isScanning: Bool = false

    struct BoundingBox {
        var min: simd_float3 = .init(repeating: Float.greatestFiniteMagnitude)
        var max: simd_float3 = .init(repeating: -Float.greatestFiniteMagnitude)

        var size: simd_float3 { max - min }
        var volume: Float { abs(size.x * size.y * size.z) }
        var center: simd_float3 { (min + max) / 2 }

        mutating func update(with point: simd_float3) {
            min = simd_min(min, point)
            max = simd_max(max, point)
        }
    }

    override init() {
        super.init()
        arView.delegate = self
        arView.session.delegate = self
        arView.automaticallyUpdatesLighting = true
        arView.antialiasingMode = .multisampling4X
        captureManager.delegate = self
        setupThermalStateObserver()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func startScan() {
        guard !isScanning else { return }

        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            delegate?.arScanner(self, showAlertWithTitle: "Device Not Supported",
                                message: "This device needs LiDAR for scanning. Try a newer iPhone or iPad with LiDAR.")
            return
        }

        let tempFolderURL = ScanLocalStorage.shared.createTempScanFolder()
        guard let tempFolderURL = tempFolderURL else {
            delegate?.arScanner(self, showAlertWithTitle: "Storage Error",
                                message: "Failed to create temporary scan folder. Please check storage and try again.")
            return
        }
        currentScanFolderURL = tempFolderURL
        captureManager.setScanFolderURL(tempFolderURL)

        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .mesh
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        if #available(iOS 14.0, *) {
            config.frameSemantics = [.smoothedSceneDepth, .sceneDepth]
        }

        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isScanning = true
        isProcessingFrames = true
        coordinates.removeAll()
        coordinateTimestamps.removeAll() // Clear timestamps
        imageCount = 0
        lastCoordinateCaptureTime = 0 // Reset capture time
        scanStartTime = Date()
        scanDuration = 0.0
        updateStatus("Ready to scan! Move your device slowly to capture the scene.", isCritical: true)
        updateDuration()
    }

    func stopScan() {
        guard isScanning else { return }
        isProcessingFrames = false
        arView.session.pause()
        isScanning = false
        if let startTime = scanStartTime {
            scanDuration = Date().timeIntervalSince(startTime)
        }
        updateStatus("Scan paused. Preparing to save...", isCritical: true)

        delegate?.arScanner(self, promptForScanName: { [weak self] name in
            guard let self = self, let tempFolderURL = self.currentScanFolderURL else { return }

            Task {
                do {
                    let (finalFolderURL, metadata) = try await ScanLocalStorage.shared.finalizeScanFolder(
                        tempFolderURL: tempFolderURL,
                        name: name,
                        coordinates: self.coordinates,
                        coordinateTimestamps: self.coordinateTimestamps, // Pass timestamps
                        imageCount: self.imageCount,
                        durationSeconds: self.scanDuration
                    )
                    guard let finalFolderURL = finalFolderURL, let metadata = metadata else {
                        DispatchQueue.main.async {
                            self.delegate?.arScanner(self, showAlertWithTitle: "Save Error",
                                                    message: "Failed to finalize scan folder. Please try again.")
                        }
                        return
                    }
                    self.currentScanFolderURL = finalFolderURL

                    do {
                        let zipData = try self.exportDataAsZip()
                        _ = ScanLocalStorage.shared.saveInputZip(zipData, to: finalFolderURL)
                    } catch {
                        os_log("Failed to save scan data: %@", log: OSLog.default, type: .error, error.localizedDescription)
                        DispatchQueue.main.async {
                            self.delegate?.arScanner(self, showAlertWithTitle: "Save Error",
                                                    message: "Failed to save scan data. Please try again.")
                        }
                        return
                    }

                    DispatchQueue.main.async {
                        self.delegate?.arScannerDidStopScanning(self)
                    }
                } catch {
                    os_log("Failed to finalize scan: %@", log: OSLog.default, type: .error, error.localizedDescription)
                    DispatchQueue.main.async {
                        self.delegate?.arScanner(self, showAlertWithTitle: "Save Error",
                                                message: "Failed to finalize scan: \(error.localizedDescription)")
                    }
                }
            }
        })
    }

    func restartScan() {
        stopScan()
        allCapturedMeshes.removeAll()
        meshNodes.values.forEach { $0.removeFromParentNode() }
        meshNodes.removeAll()
        captureManager.cleanupCaptureDirectory()
        sceneBounds = BoundingBox()
        cameraPositions.removeAll()
        lastCameraPosition = nil
        coordinates.removeAll()
        coordinateTimestamps.removeAll() // Clear timestamps
        imageCount = 0
        lastSignificantMeshUpdate = Date()
        scanStartTime = nil
        scanDuration = 0.0
        lastCoordinateCaptureTime = 0 // Reset capture time
        if let tempFolderURL = currentScanFolderURL {
            try? FileManager.default.removeItem(at: tempFolderURL)
        }
        currentScanFolderURL = nil
        updateStatus("Restarting scan! Clearing previous data...", isCritical: true)
        startScan()
    }

    func getCapturedMeshes() -> [CapturedMesh] {
        return Array(allCapturedMeshes.values)
    }

    private func exportDataAsZip() throws -> Data {
        let fileManager = FileManager.default
        let tempFolderURL = fileManager.temporaryDirectory.appendingPathComponent("ScanExport_\(UUID().uuidString)")
        let zipURL = fileManager.temporaryDirectory.appendingPathComponent("input_data_\(UUID().uuidString).zip")

        do {
            try fileManager.createDirectory(at: tempFolderURL, withIntermediateDirectories: true)

            let modelURL = tempFolderURL.appendingPathComponent("model.ply")
            let plyContent = try generatePLYContent()
            try plyContent.write(to: modelURL, atomically: true, encoding: .utf8)

            let imagesFolderURL = captureManager.captureFolderURL
            if fileManager.fileExists(atPath: imagesFolderURL.path) {
                let destinationImagesURL = tempFolderURL.appendingPathComponent("images")
                try fileManager.copyItem(at: imagesFolderURL, to: destinationImagesURL)
            }

            let success = SSZipArchive.createZipFile(atPath: zipURL.path, withContentsOfDirectory: tempFolderURL.path)
            guard success, let zipData = try? Data(contentsOf: zipURL) else {
                throw NSError(domain: "ZipError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create ZIP file"])
            }

            try fileManager.removeItem(at: tempFolderURL)
            try fileManager.removeItem(at: zipURL)
            return zipData
        } catch {
            try? fileManager.removeItem(at: tempFolderURL)
            try? fileManager.removeItem(at: zipURL)
            throw error
        }
    }

    private func generatePLYContent() throws -> String {
        guard !allCapturedMeshes.isEmpty else {
            throw NSError(domain: "No meshes", code: 0, userInfo: nil)
        }

        var vertexOffset = 0
        var combinedVertices: [SIMD3<Float>] = []
        var combinedNormals: [SIMD3<Float>] = []
        var combinedIndices: [UInt32] = []

        for mesh in allCapturedMeshes.values {
            combinedVertices.append(contentsOf: mesh.vertices)
            combinedNormals.append(contentsOf: mesh.normals)
            combinedIndices.append(contentsOf: mesh.indices.map { $0 + UInt32(vertexOffset) })
            vertexOffset += mesh.vertices.count
        }

        let combinedMesh = CapturedMesh(
            vertices: combinedVertices,
            normals: combinedNormals,
            indices: combinedIndices,
            transform: matrix_identity_float4x4
        )

        return combinedMesh.exportAsPLY()
    }

    private func process(_ meshAnchor: ARMeshAnchor) {
        guard isProcessingFrames else { return }

        let geometry = meshAnchor.geometry
        let transform = meshAnchor.transform

        updateSceneBounds(with: geometry.vertices)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            do {
                if let existingNode = self.meshNodes[meshAnchor.identifier] {
                    existingNode.removeFromParentNode()
                }

                let node = try self.createPolycamStyleNode(from: meshAnchor)
                self.arView.scene.rootNode.addChildNode(node)
                self.meshNodes[meshAnchor.identifier] = node
            } catch {
                self.updateStatus("Oops, couldn't process this mesh. Keep scanning or try restarting.", isCritical: true)
            }
        }

        meshProcessingQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                let vertices = try self.extractVertices(from: geometry.vertices)
                let normals = try self.extractNormals(from: geometry.normals)
                let indices = try self.extractIndices(from: geometry.faces)

                let mesh = CapturedMesh(
                    vertices: vertices,
                    normals: normals,
                    indices: indices,
                    transform: transform
                )

                DispatchQueue.main.async {
                    self.allCapturedMeshes[meshAnchor.identifier] = mesh
                    self.lastSignificantMeshUpdate = Date()
                    let count = self.allCapturedMeshes.count
                    self.delegate?.arScanner(self, didUpdateMeshesCount: count)
                    self.provideProgressFeedback(count: count)
                }
            } catch {
                self.updateStatus("Oops, couldn't extract mesh data. Keep scanning or try restarting.", isCritical: true)
            }
        }
    }

    private func updateSceneBounds(with vertices: ARGeometrySource) {
        for i in 0..<vertices.count {
            do {
                let vertex = try vertices.safeVertex(at: UInt32(i))
                sceneBounds.update(with: vertex)
            } catch {
                os_log("Failed to update scene bounds for vertex %d", log: OSLog.default, type: .error, i)
            }
        }
    }

    private func extractNormals(from source: ARGeometrySource) throws -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>]()
        normals.reserveCapacity(source.count)

        for i in 0..<source.count {
            let normal = try source.safeVertex(at: UInt32(i))
            normals.append(normal)
        }

        return normals
    }

    private func createPolycamStyleNode(from meshAnchor: ARMeshAnchor) throws -> SCNNode {
        let node = SCNNode()

        let solidGeo = try createSolidGeometry(from: meshAnchor)
        solidGeo.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.08)
        node.addChildNode(SCNNode(geometry: solidGeo))

        let wireGeo = try createWireframeGeometry(from: meshAnchor)
        wireGeo.firstMaterial?.diffuse.contents = UIColor.white
        wireGeo.firstMaterial?.emission.contents = UIColor.white.withAlphaComponent(0.3)
        node.addChildNode(SCNNode(geometry: wireGeo))

        node.simdTransform = meshAnchor.transform
        return node
    }

    private func createSolidGeometry(from meshAnchor: ARMeshAnchor) throws -> SCNGeometry {
        let meshGeometry = meshAnchor.geometry
        let vertices = meshGeometry.vertices
        let faces = meshGeometry.faces

        var vertexArray = [SCNVector3]()
        for i in 0..<vertices.count {
            let vertex = try vertices.safeVertex(at: UInt32(i))
            vertexArray.append(SCNVector3(vertex))
        }

        var indexArray = [Int32]()
        for faceIndex in 0..<faces.count {
            let vertexIndices = try faces.safeVertexIndices(of: faceIndex)
            indexArray += [vertexIndices.0, vertexIndices.1, vertexIndices.2]
        }

        let vertexSource = SCNGeometrySource(vertices: vertexArray)
        let element = SCNGeometryElement(indices: indexArray, primitiveType: .triangles)

        return SCNGeometry(sources: [vertexSource], elements: [element])
    }

    private func createWireframeGeometry(from meshAnchor: ARMeshAnchor) throws -> SCNGeometry {
        let meshGeometry = meshAnchor.geometry
        let vertices = meshGeometry.vertices
        let faces = meshGeometry.faces

        var vertexArray = [SCNVector3]()
        for i in 0..<vertices.count {
            let vertex = try vertices.safeVertex(at: UInt32(i))
            vertexArray.append(SCNVector3(vertex))
        }

        var lineIndices = [Int32]()
        for faceIndex in 0..<faces.count {
            let vertexIndices = try faces.safeVertexIndices(of: faceIndex)
            lineIndices += [
                vertexIndices.0, vertexIndices.1,
                vertexIndices.1, vertexIndices.2,
                vertexIndices.2, vertexIndices.0
            ]
        }

        let vertexSource = SCNGeometrySource(vertices: vertexArray)
        let element = SCNGeometryElement(indices: lineIndices, primitiveType: .line)

        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
        geometry.firstMaterial?.lightingModel = .constant
        geometry.firstMaterial?.diffuse.contents = UIColor.white
        geometry.firstMaterial?.isDoubleSided = true

        return geometry
    }

    private func extractVertices(from source: ARGeometrySource) throws -> [SIMD3<Float>] {
        var vertices = [SIMD3<Float>]()
        vertices.reserveCapacity(source.count)

        for i in 0..<source.count {
            let vertex = try source.safeVertex(at: UInt32(i))
            vertices.append(vertex)
        }

        return vertices
    }

    private func extractIndices(from source: ARGeometryElement) throws -> [UInt32] {
        var indices = [UInt32]()
        indices.reserveCapacity(source.count * 3)

        for faceIndex in 0..<source.count {
            let (i0, i1, i2) = try source.safeVertexIndices(of: faceIndex)
            indices.append(contentsOf: [UInt32(i0), UInt32(i1), UInt32(i2)])
        }

        return indices
    }

    private func shouldUpdateMessage(_ message: String, isCritical: Bool) -> Bool {
        guard !isCritical else { return true }

        let now = Date()
        let timeSinceLast = now.timeIntervalSince(lastMessageTime)

        if message.isEmpty || lastMessage == nil || message == lastMessage {
            return false
        }

        let isSimilar = message.levenshteinDistance(to: lastMessage!) < 0.7

        if timeSinceLast >= 5.0 && !isSimilar {
            lastMessageTime = now
            lastMessage = message
            return true
        }
        return false
    }

    private func updateStatus(_ message: String, isCritical: Bool = false) {
        guard isProcessingFrames else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.shouldUpdateMessage(message, isCritical: isCritical) {
                self.delegate?.arScanner(self, didUpdateStatus: message)
                os_log("Status update: %@", log: OSLog.default, type: .info, message)
            }
        }
    }

    private func updateDuration() {
        guard isScanning, let startTime = scanStartTime else { return }
        scanDuration = Date().timeIntervalSince(startTime)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.arScanner(self, didUpdateDuration: self.scanDuration)
        }
    }

    private func provideProgressFeedback(count: Int) {
        let coverage = estimateSceneCoverage()
        let completionPercentage = Int(coverage * 100)
        guard completionPercentage != lastCompletionPercentage else { return }
        lastCompletionPercentage = completionPercentage

        let progressMessages = [
            (25, "Nice start! Keep exploring the area."),
            (50, "You're halfway done! Look for missed areas."),
            (75, "Almost there! Check edges and corners."),
            (100, "Scan complete! Review for any missed spots.")
        ]

        if let (percentage, message) = progressMessages.first(where: { $0.0 == completionPercentage }) {
            updateStatus(message, isCritical: true)
        }
    }

    private func analyzeSurfaceFeatures(frame: ARFrame) {
        let featureCount = frame.rawFeaturePoints?.points.count ?? 0
        if featureCount < 150 {
            updateStatus("Low surface detail detected. Scan textured areas for better results.", isCritical: false)
        } else if featureCount > 1000 {
            updateStatus("Great surface detail! Maintain this distance from objects.", isCritical: false)
        }
    }

    private func provideScanningGuidance(frame: ARFrame) {
        let cameraPos = simd_float3(
            frame.camera.transform.columns.3.x,
            frame.camera.transform.columns.3.y,
            frame.camera.transform.columns.3.z
        )

        cameraPositions.append(cameraPos)
        if cameraPositions.count > 60 { cameraPositions.removeFirst() }

        if isMakingCircularMotion() {
            updateStatus("Good circular pattern! Now try vertical movements to cover height.", isCritical: false)
        }

        if isRepeatingPath(cameraPos: cameraPos) {
            updateStatus("You're covering the same area. Try expanding outward to new sections.", isCritical: false)
        }
    }

    private func provideTemporalGuidance() {
        let timeSinceLastMesh = Date().timeIntervalSince(lastSignificantMeshUpdate)
        if timeSinceLastMesh > 8.0 {
            updateStatus("No new details captured recently. Try moving to a new area.", isCritical: false)
        }
    }

    private func provideAngleGuidance(frame: ARFrame) {
        let cameraTiltAngle = calculateCameraTilt(frame.camera.transform)
        if cameraTiltAngle > 45 {
            updateStatus("Tilt device downward to capture lower surfaces.", isCritical: false)
        } else if cameraTiltAngle < -30 {
            updateStatus("Angle device upward to capture higher areas.", isCritical: false)
        }
    }

    private func provideCoverageFeedback() {
        let coverage = estimateSceneCoverage()
        if coverage > 0.75 {
            updateStatus("Almost complete! Check for missed spots near the edges.", isCritical: false)
        } else if coverage < 0.3 {
            updateStatus("Keep exploring! We've only covered a small portion so far.", isCritical: false)
        }
    }

    private func estimateSceneCoverage() -> Float {
        guard sceneBounds.volume > 0 else { return 0.0 }

        let coveredPoints = Float(allCapturedMeshes.count * 1000)
        let totalVolume = sceneBounds.volume
        let estimatedCoverage = Swift.min(1.0, coveredPoints / (totalVolume * 1000.0))
        return estimatedCoverage
    }

    private func calculateCameraTilt(_ transform: simd_float4x4) -> Float {
        let upVector = simd_float3(0, 1, 0)
        let cameraForward = simd_float3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        let angle = atan2(cameraForward.y, sqrt(cameraForward.x * cameraForward.x + cameraForward.z * cameraForward.z))
        return angle * 180.0 / .pi
    }

    private func isMakingCircularMotion() -> Bool {
        guard cameraPositions.count >= 20 else { return false }

        let recentPositions = cameraPositions.suffix(20)
        let center = recentPositions.reduce(simd_float3.zero) { $0 + $1 } / Float(recentPositions.count)
        let distances = recentPositions.map { simd_distance($0, center) }
        let avgDistance = distances.reduce(0, +) / Float(distances.count)
        let variance = distances.map { pow($0 - avgDistance, 2) }.reduce(0, +) / Float(distances.count)

        return variance < 0.1
    }

    private func isRepeatingPath(cameraPos: simd_float3) -> Bool {
        guard let lastPos = lastCameraPosition else {
            lastCameraPosition = cameraPos
            return false
        }

        let distance = simd_distance(cameraPos, lastPos)
        lastCameraPosition = cameraPos

        let recentPositions = cameraPositions.suffix(10)
        let avgPosition = recentPositions.reduce(simd_float3.zero) { $0 + $1 } / Float(recentPositions.count)
        let maxDistance = recentPositions.map { simd_distance($0, avgPosition) }.max() ?? 0

        return distance < 0.1 && maxDistance < 0.2
    }

    private func setupThermalStateObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }

    @objc private func thermalStateChanged(_ notification: Notification) {
        if ProcessInfo.processInfo.thermalState == .critical {
            updateStatus("Your device is getting warm. Take a quick break to cool it down.", isCritical: true)
        }
    }
}

@available(iOS 13.4, *)
extension ARScanner: ARSessionDelegate, ARSCNViewDelegate {
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard isProcessingFrames else { return }
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                process(meshAnchor)
            }
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isProcessingFrames else { return }
        captureManager.tryCapture(frame: frame)

        // Capture coordinates every 2 seconds, up to 100 points
        let currentTime = CACurrentMediaTime()
        if coordinates.count < 100 && (lastCoordinateCaptureTime == 0 || currentTime - lastCoordinateCaptureTime >= 2.0) {
            if let location = locationManager.latestLocation {
                let accuracy = location.horizontalAccuracy
                if accuracy <= 20 { // Relaxed accuracy threshold
                    let latitude = location.coordinate.latitude
                    let longitude = location.coordinate.longitude
                    // Validate coordinates
                    if (-90...90).contains(latitude) && (-180...180).contains(longitude) {
                        coordinates.append([latitude, longitude])
                        coordinateTimestamps.append(currentTime)
                        lastCoordinateCaptureTime = currentTime
                        os_log("Captured coordinate: [%f, %f] at time %f", log: OSLog.default, type: .info, latitude, longitude, currentTime)
                    } else {
                        updateStatus("Invalid GPS coordinates detected.", isCritical: false)
                    }
                } else {
                    updateStatus("Poor GPS signal (accuracy: %fm). Coordinates may be less reliable.", isCritical: false)
                }
            } else {
                updateStatus("No GPS signal available.", isCritical: false)
            }
        }

        if let lightEstimate = frame.lightEstimate?.ambientIntensity, lightEstimate < 100 {
            updateStatus("It's a bit dark here. Try adding more light for better results.", isCritical: false)
            return
        }

        switch frame.worldMappingStatus {
        case .notAvailable:
            updateStatus("Start exploring! Move slowly to map the area.", isCritical: false)
        case .limited:
            updateStatus("Keep moving slowly to help me understand the space.", isCritical: false)
        case .extending:
            updateStatus("Nice work! The map is coming together, keep going.", isCritical: false)
        case .mapped:
            updateStatus("Great job! The area is mapped, keep scanning for details.", isCritical: false)
        @unknown default:
            updateStatus("Something's off. Try moving slowly or restarting the scan.", isCritical: false)
        }

        switch frame.camera.trackingState {
        case .normal:
            break
        case .notAvailable:
            updateStatus("Hmm, I can't track right now. Try restarting the scan.", isCritical: false)
        case .limited(.excessiveMotion):
            updateStatus("Whoa, you're moving too fast! Slow down to capture details clearly.", isCritical: false)
        case .limited(.insufficientFeatures):
            updateStatus("This spot's a bit plain. Try aiming at textured surfaces.", isCritical: false)
        case .limited(.initializing):
            updateStatus("Just warming up! Move slowly to help me get started.", isCritical: false)
        case .limited(.relocalizing):
            updateStatus("Lost my place! Try moving back to where you started.", isCritical: false)
        case .limited(_):
            updateStatus("Something's off. Try moving slowly or restarting the scan.", isCritical: false)
        @unknown default:
            updateStatus("Something's off. Try moving slowly or restarting the scan.", isCritical: false)
        }

        analyzeSurfaceFeatures(frame: frame)
        provideScanningGuidance(frame: frame)
        provideTemporalGuidance()
        provideAngleGuidance(frame: frame)
        provideCoverageFeedback()
        updateDuration()
    }
}

@available(iOS 13.4, *)
extension ARScanner: ScanCaptureManagerDelegate {
    func scanCaptureManager(_ manager: ScanCaptureManager, didCaptureImage count: Int) {
        imageCount = count
    }

    func scanCaptureManagerReachedStorageLimit(_ manager: ScanCaptureManager) {
        DispatchQueue.main.async {
            self.stopScan()
            self.delegate?.arScanner(self, showAlertWithTitle: "Storage Full",
                                    message: "Storage is full! Clear some space or process your scan.")
        }
    }

    func scanCaptureManager(_ manager: ScanCaptureManager, didUpdateStatus status: String) {
        updateStatus(status, isCritical: false)
    }
}

// MARK: - GeometrySourceError
@available(iOS 13.4, *)
struct GeometrySourceError: Error {
    let message: String
}

// MARK: - ARGeometrySource Extension
@available(iOS 13.4, *)
extension ARGeometrySource {
    func safeVertex(at index: UInt32) throws -> SIMD3<Float> {
        guard index < count else {
            throw GeometrySourceError(message: "Index \(index) out of bounds (0..<\(count))")
        }
        
        let buffer = self.buffer
        let stride = self.stride
        let offset = self.offset + Int(index) * stride
        
        let pointer = buffer.contents().advanced(by: offset).assumingMemoryBound(to: SIMD3<Float>.self)
        return pointer.pointee
    }
}

// MARK: - ARGeometryElement Extension
@available(iOS 13.4, *)
extension ARGeometryElement {
    struct GeometryElementError: Error {
        let message: String
    }
    
    func safeVertexIndices(of faceIndex: Int) throws -> (Int32, Int32, Int32) {
        guard indexCountPerPrimitive == 3 else {
            throw GeometryElementError(message: "Expected triangle geometry")
        }
        
        guard faceIndex >= 0 && faceIndex < count else {
            throw GeometryElementError(message: "Face index \(faceIndex) out of bounds")
        }
        
        let bytesPerIndex = self.bytesPerIndex
        let buffer = self.buffer
        let baseOffset = faceIndex * 3 * bytesPerIndex
        let pointer = buffer.contents().advanced(by: baseOffset)
        
        if bytesPerIndex == 2 {
            let indices = pointer.assumingMemoryBound(to: UInt16.self)
            return (
                Int32(indices[0]),
                Int32(indices[1]),
                Int32(indices[2])
            )
        } else {
            let indices = pointer.assumingMemoryBound(to: Int32.self)
            return (
                indices[0],
                indices[1],
                indices[2]
            )
        }
    }
}

// MARK: - String Extension
extension String {
    func levenshteinDistance(to other: String) -> Double {
        if self.isEmpty && other.isEmpty {
            return 0.0
        }
        if self.isEmpty || other.isEmpty {
            return 1.0
        }
        
        let m = self.count
        let n = other.count
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m {
            matrix[i][0] = i
        }
        for j in 0...n {
            matrix[0][j] = j
        }
        
        for i in 1...m {
            for j in 1...n {
                let cost = self[self.index(self.startIndex, offsetBy: i - 1)] == other[other.index(other.startIndex, offsetBy: j - 1)] ? 0 : 1
                matrix[i][j] = Swift.min(
                    matrix[i-1][j] + 1,
                    matrix[i][j-1] + 1,
                    matrix[i-1][j-1] + cost
                )
            }
        }
        
        return Double(matrix[m][n]) / Double(max(m, n))
    }
}

// MARK: - ARCamera.TrackingState Extension
extension ARCamera.TrackingState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .normal:
            return "Normal"
        case .notAvailable:
            return "Not Available"
        case .limited(let reason):
            switch reason {
            case .excessiveMotion:
                return "Limited - Excessive Motion"
            case .insufficientFeatures:
                return "Limited - Insufficient Features"
            case .initializing:
                return "Limited - Initializing"
            case .relocalizing:
                return "Limited - Relocalizing"
            @unknown default:
                return "Limited - Unknown Reason"
            }
        }
    }
}

@available(iOS 13.4, *)
class ScanViewController: UIViewController {
    private let arScanner = ARScanner()
    let captureManager = ScanCaptureManager()
    private let controlPanel = ControlPanel()
    private let closeButton = UIButton(type: .system)
    private var activityIndicator: UIActivityIndicatorView?
    private var isPresentingPreview: Bool = false
    private var channel: FlutterMethodChannel?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupFlutterChannel()
        setupUI()
        setupDelegates()
        checkCameraPermission()
        setupActivityIndicator()
        captureManager.delegate = self
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arScanner.stopScan()
        if !isPresentingPreview {
            captureManager.cleanupCaptureDirectory()
            if let tempFolderURL = arScanner.currentScanFolderURL {
                try? FileManager.default.removeItem(at: tempFolderURL)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isPresentingPreview = false
    }

    private func setupFlutterChannel() {
        if let flutterController = UIApplication.shared.delegate?.window??.rootViewController as? FlutterViewController {
            channel = FlutterMethodChannel(name: "com.demo.channel/message", binaryMessenger: flutterController.binaryMessenger)
        } else {
            os_log("Failed to initialize Flutter method channel", log: OSLog.default, type: .error)
        }
    }

    private func setupUI() {
        view.backgroundColor = .black

        view.addSubview(arScanner.view)
        view.addSubview(controlPanel)
        view.addSubview(closeButton)

        arScanner.view.translatesAutoresizingMaskIntoConstraints = false
        controlPanel.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        closeButton.layer.cornerRadius = 20
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            arScanner.view.topAnchor.constraint(equalTo: view.topAnchor),
            arScanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            arScanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            arScanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            controlPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            controlPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            controlPanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),

            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    private func setupDelegates() {
        arScanner.delegate = self
        controlPanel.delegate = self
    }

    private func setupActivityIndicator() {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.center = view.center
        indicator.hidesWhenStopped = true
        view.addSubview(indicator)
        activityIndicator = indicator
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            controlPanel.updateUIForScanningState(isScanning: false, hasMeshes: false)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.controlPanel.updateUIForScanningState(isScanning: false, hasMeshes: false)
                    } else {
                        self?.showAlert(title: "Permission Denied", message: "Camera access is required for AR scanning.")
                    }
                }
            }
        default:
            showAlert(title: "Permission Denied", message: "Camera access is required for AR scanning.")
        }
    }

    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }

    private func showModelView() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isPresentingPreview = true
            let previewVC = ModelViewController()
            previewVC.capturedMeshes = self.arScanner.getCapturedMeshes()
            previewVC.currentScanFolderURL = self.arScanner.currentScanFolderURL
            previewVC.modalPresentationStyle = .fullScreen
            self.present(previewVC, animated: true)
        }
    }

    @objc private func closeTapped() {
        arScanner.stopScan()
        captureManager.cleanupCaptureDirectory()
        if let tempFolderURL = arScanner.currentScanFolderURL {
            try? FileManager.default.removeItem(at: tempFolderURL)
        }
        channel?.invokeMethod("closeARModule", arguments: nil) { result in
            if let error = result as? FlutterError {
                os_log("Failed to invoke closeARModule: %@", log: OSLog.default, type: .error, error.message ?? "Unknown error")
            }
        }
        generateHapticFeedback()
        DispatchQueue.main.async {
            var presentingVC = self.presentingViewController
            while let parent = presentingVC?.presentingViewController {
                presentingVC = parent
            }
            presentingVC?.dismiss(animated: true, completion: nil)
        }
    }

    private func generateHapticFeedback(_ type: UINotificationFeedbackGenerator.FeedbackType = .success) {
        let feedbackGenerator = UINotificationFeedbackGenerator()
        feedbackGenerator.prepare()
        feedbackGenerator.notificationOccurred(type)
    }
}

@available(iOS 13.4, *)
extension ScanViewController: ARScannerDelegate {
    func arScanner(_ scanner: ARScanner, didUpdateDuration duration: Double) {
        DispatchQueue.main.async {
            self.controlPanel.updateDuration(duration)
        }
    }

    func arScanner(_ scanner: ARScanner, didUpdateStatus status: String) {
        DispatchQueue.main.async {
            self.controlPanel.updateStatus(status)
        }
    }

    func arScanner(_ scanner: ARScanner, didUpdateMeshesCount count: Int) {
        DispatchQueue.main.async {
            self.controlPanel.updateUIForScanningState(isScanning: scanner.isScanning,
                                                      hasMeshes: count > 0)
        }
    }

    func arScannerDidStopScanning(_ scanner: ARScanner) {
        DispatchQueue.main.async {
            self.activityIndicator?.startAnimating()
            self.controlPanel.updateUIForScanningState(isScanning: false,
                                                      hasMeshes: !scanner.getCapturedMeshes().isEmpty)
            if !scanner.getCapturedMeshes().isEmpty {
                if let folderURL = scanner.currentScanFolderURL {
                    let metadataURL = folderURL.appendingPathComponent("metadata.json")
                    do {
                        let data = try Data(contentsOf: metadataURL)
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let metadata = try decoder.decode(ScanMetadata.self, from: data)
                        let dateFormatter = ISO8601DateFormatter()
                        let usdzURL = ScanLocalStorage.shared.hasUSDZModel(in: folderURL) ? folderURL.appendingPathComponent("model.usdz") : nil
                        self.channel?.invokeMethod("scanComplete", arguments: [
                            "scanID": metadata.scanID,
                            "name": metadata.name,
                            "usdzPath": usdzURL?.path as Any,
                            "folderPath": folderURL.path,
                            "hasUSDZ": usdzURL != nil,
                            "timestamp": dateFormatter.string(from: metadata.timestamp),
                            "coordinates": metadata.coordinates ?? [],
                            "coordinateTimestamps": metadata.coordinateTimestamps ?? [], // Include timestamps
                            "locationName": metadata.locationName ?? "",
                            "modelSizeBytes": metadata.modelSizeBytes ?? 0,
                            "imageCount": metadata.imageCount,
                            "durationSeconds": metadata.durationSeconds ?? 0.0
                        ]) { result in
                            if let error = result as? FlutterError {
                                os_log("Failed to invoke scanComplete: %@", log: OSLog.default, type: .error, error.message ?? "Unknown error")
                            }
                            DispatchQueue.main.async {
                                self.activityIndicator?.stopAnimating()
                                self.showModelView()
                            }
                        }
                    } catch {
                        os_log("Failed to read metadata: %@", log: OSLog.default, type: .error, error.localizedDescription)
                        self.activityIndicator?.stopAnimating()
                        self.showAlert(title: "Save Error", message: "Failed to read scan metadata. Please try again.")
                    }
                } else {
                    self.activityIndicator?.stopAnimating()
                    self.showAlert(title: "Save Error", message: "Scan folder not found. Please try again.")
                }
            } else {
                self.activityIndicator?.stopAnimating()
            }
        }
    }

    func arScanner(_ scanner: ARScanner, showAlertWithTitle title: String, message: String) {
        showAlert(title: title, message: message)
    }

    func arScanner(_ scanner: ARScanner, didCaptureDebugImage image: UIImage) {
        // No action needed for debug image
    }

    func arScanner(_ scanner: ARScanner, promptForScanName completion: @escaping (String?) -> Void) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "Name Your Scan", message: "Enter a name for this scan.", preferredStyle: .alert)
            alert.addTextField { textField in
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd_HHmm"
                textField.text = ""
                textField.placeholder = "Enter scan name"
            }

            alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
                let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
                completion(name)
            })
            alert.addAction(UIAlertAction(title: "Skip", style: .cancel) { _ in
                completion(nil)
            })

            self.present(alert, animated: true)
        }
    }
}

// MARK: - ScanCaptureManagerDelegate
@available(iOS 13.4, *)
extension ScanViewController: ScanCaptureManagerDelegate {
    func scanCaptureManagerReachedStorageLimit(_ manager: ScanCaptureManager) {
        DispatchQueue.main.async {
            self.arScanner.stopScan()
            self.showAlert(
                title: "Storage Full",
                message: "Storage is full! Clear some space or process your scan."
            )
        }
    }

    func scanCaptureManager(_ manager: ScanCaptureManager, didUpdateStatus status: String) {
        DispatchQueue.main.async {
            self.controlPanel.updateStatus(status)
        }
    }

    func scanCaptureManager(_ manager: ScanCaptureManager, didCaptureImage count: Int) {
        // No action needed here; count is passed to ARScanner
    }
}

// MARK: - ControlPanelDelegate
@available(iOS 13.4, *)
extension ScanViewController: ControlPanelDelegate {
    func controlPanelDidTapStart(_ controlPanel: ControlPanel) {
        arScanner.startScan()
        generateHapticFeedback()
    }

    func controlPanelDidTapStop(_ controlPanel: ControlPanel) {
        arScanner.stopScan()
        generateHapticFeedback()
    }
}

protocol ScanCaptureManagerDelegate: AnyObject {
    func scanCaptureManagerReachedStorageLimit(_ manager: ScanCaptureManager)
    func scanCaptureManager(_ manager: ScanCaptureManager, didUpdateStatus status: String)
    func scanCaptureManager(_ manager: ScanCaptureManager, didCaptureImage count: Int)
}

class ScanCaptureManager {
    private let fileManager = FileManager.default
    var captureFolderURL: URL
    private var scanFolderURL: URL?
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
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        captureFolderURL = appSupport.appendingPathComponent("ScanCapture")
        cleanupCaptureDirectory()
        createCaptureDirectory()
    }

    func setScanFolderURL(_ url: URL) {
        scanFolderURL = url
    }

    func tryCapture(frame: ARFrame) {
        guard shouldCapture(frame: frame) else { return }

        if let processedImage = preprocessImage(frame.capturedImage) {
            saveProcessedImage(processedImage, frame: frame)
            saveCameraTransform(transform: frame.camera.transform, frame: frame)
            imageIndex += 1
            delegate?.scanCaptureManager(self, didCaptureImage: imageIndex)

            if imageIndex % 10 == 0 {
                ensureStorageLimit()
            }
        }
    }

    private func shouldCapture(frame: ARFrame) -> Bool {
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastCaptureTime > Double(optimalFrameInterval)/30.0 else {
            return false
        }

        let currentPosition = simd_float3(
            frame.camera.transform.columns.3.x,
            frame.camera.transform.columns.3.y,
            frame.camera.transform.columns.3.z
        )
        if let lastPosition = lastCameraPosition {
            let distance = simd_distance(currentPosition, lastPosition)
            guard distance >= minMovementDistance else {
                delegate?.scanCaptureManager(self, didUpdateStatus: "Skipping - insufficient movement")
                return false
            }
        }

        let avgBrightness = frame.lightEstimate?.ambientIntensity ?? 1000
        guard (300...2000).contains(avgBrightness) else {
            delegate?.scanCaptureManager(self, didUpdateStatus: "Skipping - poor lighting")
            return false
        }

        if case .limited(.excessiveMotion) = frame.camera.trackingState {
            delegate?.scanCaptureManager(self, didUpdateStatus: "Skipping - excessive motion detected")
            return false
        }

        let qualityScore = calculateQualityScore(frame: frame)
        adjustCaptureRate(qualityScore: qualityScore)

        lastCameraPosition = currentPosition
        lastCaptureTime = currentTime
        return true
    }

    private func calculateQualityScore(frame: ARFrame) -> Float {
        var score: Float = 0

        switch frame.camera.trackingState {
        case .normal: score += 0.4
        case .limited: score += 0.2
        default: score += 0
        }

        if let rawFeaturePoints = frame.rawFeaturePoints {
            let featureDensity = Float(rawFeaturePoints.points.count) / 1000.0
            score += min(featureDensity, 0.3)
        }

        if let lightEstimate = frame.lightEstimate {
            let normalizedLight = Float((lightEstimate.ambientIntensity - 300) / 1700.0)
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

        let filters = ciImage.autoAdjustmentFilters(options: [.enhance: true])
        var processedImage = ciImage
        for filter in filters {
            filter.setValue(processedImage, forKey: kCIInputImageKey)
            processedImage = filter.outputImage ?? processedImage
        }

        let context = CIContext()
        guard let cgImage = context.createCGImage(processedImage, from: processedImage.extent) else {
            delegate?.scanCaptureManager(self, didUpdateStatus: "Failed to process image")
            return nil
        }

        return cgImage
    }

    private func saveProcessedImage(_ cgImage: CGImage, frame: ARFrame) {
        let uiImage = UIImage(cgImage: cgImage)
        var imageURL = captureFolderURL.appendingPathComponent("image_\(imageIndex).jpg")

        if let jpegData = uiImage.jpegData(compressionQuality: 0.9) {
            do {
                try jpegData.write(to: imageURL)
                var resourceValues = URLResourceValues()
                resourceValues.isExcludedFromBackup = true
                try imageURL.setResourceValues(resourceValues)
                currentStorageSize += Int64(jpegData.count)

                if imageIndex % 20 == 0 {
                    let debugImage = debugVisualizeFeatures(image: uiImage)
                    var debugURL = captureFolderURL.appendingPathComponent("debug_\(imageIndex).jpg")
                    if let debugJpegData = debugImage.jpegData(compressionQuality: 0.8) {
                        try debugJpegData.write(to: debugURL)
                        try debugURL.setResourceValues(resourceValues)
                        currentStorageSize += Int64(debugJpegData.count)
                    }
                }
            } catch {
                os_log("Failed to save image: %@", log: logger, type: .error, error.localizedDescription)
            }
        }
    }

    private func debugVisualizeFeatures(image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }

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
            os_log("Feature detection error: %@", log: logger, type: .error, error.localizedDescription)
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
            "transform": [
                [transform[0][0], transform[0][1], transform[0][2], transform[0][3]],
                [transform[1][0], transform[1][1], transform[1][2], transform[1][3]],
                [transform[2][0], transform[2][1], transform[2][2], transform[2][3]],
                [transform[3][0], transform[3][1], transform[3][2], transform[3][3]]
            ],
            "confidence": confidence,
            "timestamp": CACurrentMediaTime(),
            "light_estimate": frame.lightEstimate?.ambientIntensity ?? 0,
            "tracking_state": frame.camera.trackingState.description,
            "feature_count": frame.rawFeaturePoints?.points.count ?? 0
        ]

        var poseURL = captureFolderURL.appendingPathComponent("image_\(imageIndex)_pose.json")
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: poseData, options: [.prettyPrinted])
            try jsonData.write(to: poseURL)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try poseURL.setResourceValues(resourceValues)
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
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try captureFolderURL.setResourceValues(resourceValues)
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

@available(iOS 13.4, *)
class ModelViewController: UIViewController, QLPreviewControllerDataSource, UIDocumentPickerDelegate {
    private let sceneView = SCNView()
    private let processButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let downloadButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    var capturedMeshes: [CapturedMesh] = []
    var currentScanFolderURL: URL?
    private var channel: FlutterMethodChannel?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var modelUrl: URL?
    private var downloadedFileURL: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupFlutterChannel()
        setupUI()
        setupScene()
        captureAndSaveSnapshot() // Capture snapshot after setting up the scene
    }

    private func captureAndSaveSnapshot() {
        guard let scanFolderURL = currentScanFolderURL else {
            os_log("No scan folder URL to save snapshot", log: OSLog.default, type: .error)
            return
        }

        // Capture snapshot from SCNView
        let snapshot = sceneView.snapshot()
        var snapshotURL = scanFolderURL.appendingPathComponent("snapshot.png")
        
        do {
            // Save snapshot as PNG
            if let data = snapshot.pngData() {
                try data.write(to: snapshotURL)
                var resourceValues = URLResourceValues()
                resourceValues.isExcludedFromBackup = true
                try snapshotURL.setResourceValues(resourceValues)
                os_log("Saved snapshot to: %@", log: OSLog.default, type: .info, snapshotURL.path)
                
                // Update metadata with snapshot path
                var metadataURL = scanFolderURL.appendingPathComponent("metadata.json")
                if FileManager.default.fileExists(atPath: metadataURL.path) {
                    let data = try Data(contentsOf: metadataURL)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    var metadata = try decoder.decode(ScanMetadata.self, from: data)
                    metadata.snapshotPath = "snapshot.png" // Store relative path
                    
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let updatedData = try encoder.encode(metadata)
                    try updatedData.write(to: metadataURL)
                    try metadataURL.setResourceValues(resourceValues)
                    os_log("Updated metadata with snapshot path", log: OSLog.default, type: .info)
                }
            }
        } catch {
            os_log("Failed to save snapshot: %@", log: OSLog.default, type: .error, error.localizedDescription)
        }
    }
    
    private func setupFlutterChannel() {
        if let flutterController = UIApplication.shared.delegate?.window??.rootViewController as? FlutterViewController {
            channel = FlutterMethodChannel(name: "com.demo.channel/message", binaryMessenger: flutterController.binaryMessenger)
        } else {
            os_log("Failed to initialize Flutter method channel", log: OSLog.default, type: .error)
        }
    }
    
    private func setupUI() {
        view.backgroundColor = .black
        view.addSubview(sceneView)
        view.addSubview(closeButton)
        view.addSubview(backButton)
        view.addSubview(processButton)
        view.addSubview(downloadButton)
        view.addSubview(shareButton)
        view.addSubview(statusLabel)
        view.addSubview(loadingIndicator)
        
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.translatesAutoresizingMaskIntoConstraints = false
        processButton.translatesAutoresizingMaskIntoConstraints = false
        downloadButton.translatesAutoresizingMaskIntoConstraints = false
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure buttons
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        closeButton.layer.cornerRadius = 20
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = .white
        backButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        backButton.layer.cornerRadius = 20
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        
        processButton.setTitle("Process", for: .normal)
        processButton.setTitleColor(.white, for: .normal)
        processButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
        processButton.layer.cornerRadius = 10
        processButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        processButton.addTarget(self, action: #selector(processTapped), for: .touchUpInside)
        
        downloadButton.setTitle("Download", for: .normal)
        downloadButton.setTitleColor(.white, for: .normal)
        downloadButton.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.8)
        downloadButton.layer.cornerRadius = 10
        downloadButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        downloadButton.addTarget(self, action: #selector(downloadTapped), for: .touchUpInside)
        downloadButton.isHidden = true
        
        shareButton.setTitle("Share", for: .normal)
        shareButton.setTitleColor(.white, for: .normal)
        shareButton.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.8)
        shareButton.layer.cornerRadius = 10
        shareButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        shareButton.isHidden = true
        
        statusLabel.text = ""
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 16, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        statusLabel.layer.cornerRadius = 8
        statusLabel.layer.masksToBounds = true
        
        loadingIndicator.color = .white
        loadingIndicator.hidesWhenStopped = true
        
        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),
            
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            backButton.widthAnchor.constraint(equalToConstant: 40),
            backButton.heightAnchor.constraint(equalToConstant: 40),
            
            processButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            processButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            processButton.widthAnchor.constraint(equalToConstant: 100),
            processButton.heightAnchor.constraint(equalToConstant: 44),
            
            downloadButton.bottomAnchor.constraint(equalTo: processButton.topAnchor, constant: -10),
            downloadButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            downloadButton.widthAnchor.constraint(equalToConstant: 100),
            downloadButton.heightAnchor.constraint(equalToConstant: 44),
            
            shareButton.bottomAnchor.constraint(equalTo: downloadButton.topAnchor, constant: -10),
            shareButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            shareButton.widthAnchor.constraint(equalToConstant: 100),
            shareButton.heightAnchor.constraint(equalToConstant: 44),
            
            statusLabel.bottomAnchor.constraint(equalTo: processButton.topAnchor, constant: -20),
            statusLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func setupScene() {
        let scene = SCNScene()
        sceneView.scene = scene
        sceneView.allowsCameraControl = true
        sceneView.backgroundColor = .black
        sceneView.autoenablesDefaultLighting = true
        
        let modelNode = SCNNode()
        for mesh in capturedMeshes {
            let geometry = createGeometry(from: mesh)
            let node = SCNNode(geometry: geometry)
            guard mesh.transform.count == 4, mesh.transform.allSatisfy({ $0.count == 4 }) else {
                os_log("Invalid transform matrix for mesh", log: OSLog.default, type: .error)
                continue
            }
            let transform = simd_float4x4(
                SIMD4<Float>(mesh.transform[0][0], mesh.transform[0][1], mesh.transform[0][2], mesh.transform[0][3]),
                SIMD4<Float>(mesh.transform[1][0], mesh.transform[1][1], mesh.transform[1][2], mesh.transform[1][3]),
                SIMD4<Float>(mesh.transform[2][0], mesh.transform[2][1], mesh.transform[2][2], mesh.transform[2][3]),
                SIMD4<Float>(mesh.transform[3][0], mesh.transform[3][1], mesh.transform[3][2], mesh.transform[3][3])
            )
            node.simdTransform = transform
            modelNode.addChildNode(node)
        }
        
        let (min, max) = modelNode.boundingBox
        let minSIMD = SIMD3<Float>(min.x, min.y, min.z)
        let maxSIMD = SIMD3<Float>(max.x, max.y, max.z)
        let center = (minSIMD + maxSIMD) * 0.5
        let extents = maxSIMD - minSIMD
        let maxExtent = Swift.max(extents.x, extents.y, extents.z)
        let scale = maxExtent > 0 ? 1.0 / maxExtent : 1.0
        modelNode.scale = SCNVector3(scale, scale, scale)
        modelNode.position = SCNVector3(-center.x * scale, -center.y * scale, -center.z * scale)
        
        scene.rootNode.addChildNode(modelNode)
        
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 2)
        scene.rootNode.addChildNode(cameraNode)
        
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.position = SCNVector3(0, 10, 10)
        scene.rootNode.addChildNode(lightNode)
    }
    
    private func createGeometry(from mesh: CapturedMesh) -> SCNGeometry {
        let vertexSource = SCNGeometrySource(vertices: mesh.vertices.map { SCNVector3($0) })
        let normalSource = SCNGeometrySource(normals: mesh.normals.map { SCNVector3($0) })
        let indexData = Data(bytes: mesh.indices, count: mesh.indices.count * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(data: indexData, primitiveType: .triangles, primitiveCount: mesh.indices.count / 3, bytesPerIndex: MemoryLayout<UInt32>.size)
        
        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
        geometry.firstMaterial?.diffuse.contents = UIColor.gray
        geometry.firstMaterial?.isDoubleSided = true
        return geometry
    }
    
    @objc private func processTapped() {
        guard let scanFolderURL = currentScanFolderURL else {
            showErrorAlert(message: "No scan folder available for processing.")
            return
        }
        
        processButton.isEnabled = false
        processButton.setTitle("Processing...", for: .normal)
        loadingIndicator.startAnimating()
        
        let zipURL = scanFolderURL.appendingPathComponent("input_data.zip")
        
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            guard let self = self else { return }
            os_log("⚠️ Background task expired", log: OSLog.default, type: .error)
            DispatchQueue.main.async {
                self.showErrorAlert(message: "Processing timed out due to app suspension. Please try again.")
                self.processButton.isEnabled = true
                self.processButton.setTitle("Process", for: .normal)
                self.loadingIndicator.stopAnimating()
                self.statusLabel.text = ""
                self.endBackgroundTask()
                // Set status to pending on timeout
                self.updateScanStatus(to: "pending", for: scanFolderURL)
            }
        }
        
        do {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: zipURL.path) else {
                throw NSError(domain: "FileError", code: -1, userInfo: [NSLocalizedDescriptionKey: "ZIP file not found at \(zipURL.path)"])
            }
            let zipAttributes = try fileManager.attributesOfItem(atPath: zipURL.path)
            let zipSizeBytes = zipAttributes[.size] as? Int64 ?? 0
            let zipSizeMB = Double(zipSizeBytes) / (1024 * 1024)
            let estimatedMinutes = (zipSizeMB / 50.0) * 2.0
            let estimatedTimeText = String(format: "%.1f", estimatedMinutes)
            DispatchQueue.main.async {
                self.statusLabel.text = String(format: "ZIP file created (%.2f MB). Processing may take ~%@ minutes...", zipSizeMB, estimatedTimeText)
            }
            
            channel?.invokeMethod("updateProcessingStatus", arguments: ["status": "processing"])
            
            processZipFile(at: zipURL) { [weak self] result in
                guard let self = self else {
                    self?.endBackgroundTask()
                    return
                }
                
                DispatchQueue.main.async {
                    self.processButton.isEnabled = true
                    self.processButton.setTitle("Process", for: .normal)
                    self.loadingIndicator.stopAnimating()
                }
                
                switch result {
                case .success(let usdzURL, _):
                    DispatchQueue.main.async {
                        do {
                            let scene = try SCNScene(url: usdzURL, options: nil)
                            self.sceneView.scene = scene
                            self.statusLabel.text = "Model loaded successfully."
                            self.downloadedFileURL = usdzURL
                            self.downloadButton.isHidden = false
                            self.shareButton.isHidden = false
                            os_log("✅ Successfully loaded and displayed USDZ model", log: OSLog.default, type: .info)
                            self.channel?.invokeMethod("processingComplete", arguments: ["usdzPath": usdzURL.path]) { result in
                                if let error = result as? FlutterError {
                                    os_log("Failed to invoke processingComplete: %@", log: OSLog.default, type: .error, error.message ?? "Unknown error")
                                }
                            }
                            // Update scan status to "uploaded"
                            let success = ScanLocalStorage.shared.updateScanStatus("uploaded", for: scanFolderURL)
                            if !success {
                                os_log("⚠️ Failed to update scan status to uploaded", log: OSLog.default, type: .error)
                            }
                            self.endBackgroundTask()
                        } catch {
                            os_log("❌ Failed to load USDZ model with SceneKit: %@", log: OSLog.default, type: .error, error.localizedDescription)
                            self.downloadedFileURL = usdzURL
                            self.downloadButton.isHidden = false
                            self.shareButton.isHidden = false
                            let previewController = QLPreviewController()
                            previewController.dataSource = self
                            self.present(previewController, animated: true) {
                                self.statusLabel.text = "Model loaded in Quick Look."
                                os_log("✅ Loaded USDZ model in QLPreviewController", log: OSLog.default, type: .info)
                                self.channel?.invokeMethod("processingComplete", arguments: ["usdzPath": usdzURL.path]) { result in
                                    if let error = result as? FlutterError {
                                        os_log("Failed to invoke processingComplete: %@", log: OSLog.default, type: .error, error.message ?? "Unknown error")
                                    }
                                }
                                // Update scan status to "uploaded"
                                let success = ScanLocalStorage.shared.updateScanStatus("uploaded", for: scanFolderURL)
                                if !success {
                                    os_log("⚠️ Failed to update scan status to uploaded", log: OSLog.default, type: .error)
                                }
                                self.endBackgroundTask()
                            }
                        }
                    }
                case .failure(let error, let modelUrl):
                    DispatchQueue.main.async {
                        self.showErrorAlertWithLink(message: error.message ?? "Unknown error")
                        self.statusLabel.text = "Processing failed."
                        // Update scan status based on error type
                        let isServerError = ["API_REQUEST_FAILED", "API_STATUS_ERROR", "INVALID_MODEL_URL", "PARSE_FAILED"].contains(error.code)
                        let newStatus = isServerError ? "failed" : "pending"
                        let success = ScanLocalStorage.shared.updateScanStatus(newStatus, for: scanFolderURL)
                        if !success {
                            os_log("⚠️ Failed to update scan status to %@", log: OSLog.default, type: .error, newStatus)
                        }
                        self.endBackgroundTask()
                    }
                }
            }
        } catch {
            os_log("❌ Failed to process: %@", log: OSLog.default, type: .error, error.localizedDescription)
            DispatchQueue.main.async {
                self.showErrorAlert(message: error.localizedDescription)
                self.processButton.isEnabled = true
                self.processButton.setTitle("Process", for: .normal)
                self.loadingIndicator.stopAnimating()
                self.statusLabel.text = ""
                self.endBackgroundTask()
                // Set status to pending for local errors
                if let scanFolderURL = self.currentScanFolderURL {
                    let success = ScanLocalStorage.shared.updateScanStatus("pending", for: scanFolderURL)
                    if !success {
                        os_log("⚠️ Failed to update scan status to pending", log: OSLog.default, type: .error)
                    }
                }
            }
        }
    }
    
    enum ProcessingResult {
        case success(URL, Int64)
        case failure(FlutterError, URL?)
    }
    
    func processZipFile(at zipURL: URL, completion: @escaping (ProcessingResult) -> Void) {
        guard let scanFolderURL = currentScanFolderURL else {
            completion(.failure(FlutterError(
                code: "NO_SCAN_FOLDER",
                message: "No scan folder available for processing.",
                details: nil
            ), nil))
            return
        }
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: zipURL.path) else {
            completion(.failure(FlutterError(
                code: "FILE_NOT_FOUND",
                message: "ZIP file not found at \(zipURL.path)",
                details: nil
            ), nil))
            return
        }
        
        guard let zipData = try? Data(contentsOf: zipURL) else {
            completion(.failure(FlutterError(
                code: "FILE_READ_ERROR",
                message: "Failed to read ZIP file",
                details: nil
            ), nil))
            return
        }
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 1800
        let session = URLSession(configuration: configuration)
        
        let url = URL(string: "http://213.73.97.120/api/process")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
        request.httpBody = zipData
        
        channel?.invokeMethod("updateProcessingStatus", arguments: ["status": "uploading"])
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                completion(.failure(FlutterError(
                    code: "CONTROLLER_DEALLOCATED",
                    message: "ModelViewController deallocated during processing",
                    details: nil
                ), nil))
                return
            }
            
            if let error = error {
                os_log("❌ API request failed: %@", log: OSLog.default, type: .error, error.localizedDescription)
                completion(.failure(FlutterError(
                    code: "API_REQUEST_FAILED",
                    message: "API request failed: \(error.localizedDescription)",
                    details: nil
                ), nil))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                os_log("❌ API returned non-200 status: %d", log: OSLog.default, type: .error, statusCode)
                completion(.failure(FlutterError(
                    code: "API_STATUS_ERROR",
                    message: "API returned status code: \(statusCode)",
                    details: nil
                ), nil))
                return
            }
            
            guard let data = data else {
                os_log("❌ No data received from API", log: OSLog.default, type: .error)
                completion(.failure(FlutterError(
                    code: "NO_DATA",
                    message: "No data received from API",
                    details: nil
                ), nil))
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                guard let modelUrlString = json?["modelUrl"] as? String,
                      let modelUrl = URL(string: modelUrlString) else {
                    os_log("❌ Invalid model URL in response", log: OSLog.default, type: .error)
                    completion(.failure(FlutterError(
                        code: "INVALID_MODEL_URL",
                        message: "Invalid model URL in response",
                        details: nil
                    ), nil))
                    return
                }
                
                self.modelUrl = modelUrl
                self.downloadAndDisplayModel(from: modelUrl, scanFolderURL: scanFolderURL, completion: completion)
            } catch {
                os_log("❌ Failed to parse API response: %@", log: OSLog.default, type: .error, error.localizedDescription)
                completion(.failure(FlutterError(
                    code: "PARSE_FAILED",
                    message: "Failed to parse API response: \(error.localizedDescription)",
                    details: nil
                ), nil))
            }
        }
        task.resume()
    }
    
    private func downloadAndDisplayModel(from modelUrl: URL, scanFolderURL: URL, completion: @escaping (ProcessingResult) -> Void) {
        DispatchQueue.main.async {
            self.statusLabel.text = "Downloading model..."
            self.loadingIndicator.startAnimating()
        }
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 600
        let session = URLSession(configuration: configuration)
        
        channel?.invokeMethod("updateProcessingStatus", arguments: ["status": "downloading"])
        
        let task = session.downloadTask(with: modelUrl) { [weak self] tempURL, response, error in
            guard let self = self else {
                completion(.failure(FlutterError(
                    code: "CONTROLLER_DEALLOCATED",
                    message: "ModelViewController deallocated during download",
                    details: nil
                ), modelUrl))
                return
            }
            
            DispatchQueue.main.async {
                self.loadingIndicator.stopAnimating()
            }
            
            if let error = error {
                os_log("❌ Failed to download model: %@", log: OSLog.default, type: .error, error.localizedDescription)
                completion(.failure(FlutterError(
                    code: "DOWNLOAD_FAILED",
                    message: "Failed to download model: \(error.localizedDescription)",
                    details: ["modelUrl": modelUrl.absoluteString]
                ), modelUrl))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                os_log("❌ Model download returned non-200 status: %d", log: OSLog.default, type: .error, statusCode)
                completion(.failure(FlutterError(
                    code: "DOWNLOAD_STATUS_ERROR",
                    message: "Model download failed with status: \(statusCode)",
                    details: ["modelUrl": modelUrl.absoluteString]
                ), modelUrl))
                return
            }
            
            guard let tempURL = tempURL else {
                os_log("❌ No file URL for downloaded model", log: OSLog.default, type: .error)
                completion(.failure(FlutterError(
                    code: "NO_FILE_URL",
                    message: "No file URL for downloaded model",
                    details: ["modelUrl": modelUrl.absoluteString]
                ), modelUrl))
                return
            }
            
            let fileManager = FileManager.default
            var usdzURL = scanFolderURL.appendingPathComponent("model.usdz")
            do {
                try fileManager.moveItem(at: tempURL, to: usdzURL)
                var resourceValues = URLResourceValues()
                resourceValues.isExcludedFromBackup = true
                try usdzURL.setResourceValues(resourceValues)
                
                if try self.validateUSDZFile(at: usdzURL) {
                    let zipAttributes = try fileManager.attributesOfItem(atPath: scanFolderURL.appendingPathComponent("input_data.zip").path)
                    let zipSize = zipAttributes[.size] as? Int64 ?? 0
                    let usdzAttributes = try fileManager.attributesOfItem(atPath: usdzURL.path)
                    let usdzSize = usdzAttributes[.size] as? Int64 ?? 0
                    let totalSize = zipSize + usdzSize
                    
                    // Update metadata with model size and snapshot path
                    var metadataURL = scanFolderURL.appendingPathComponent("metadata.json")
                    if fileManager.fileExists(atPath: metadataURL.path) {
                        let data = try Data(contentsOf: metadataURL)
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        var metadata = try decoder.decode(ScanMetadata.self, from: data)
                        metadata.modelSizeBytes = totalSize
                        metadata.status = "uploaded"
                        metadata.snapshotPath = "snapshot.png" // Ensure snapshot path is set
                        
                        let encoder = JSONEncoder()
                        encoder.dateEncodingStrategy = .iso8601
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        let updatedData = try encoder.encode(metadata)
                        try updatedData.write(to: metadataURL)
                        try metadataURL.setResourceValues(resourceValues)
                    }
                    
                    // Try loading in SCNView first
                    do {
                        let scene = try SCNScene(url: usdzURL, options: nil)
                        self.sceneView.scene = scene
                        // Capture new snapshot after loading USDZ
                        let snapshot = self.sceneView.snapshot()
                        var snapshotURL = scanFolderURL.appendingPathComponent("snapshot.png")
                        if let data = snapshot.pngData() {
                            try data.write(to: snapshotURL)
                            try snapshotURL.setResourceValues(resourceValues)
                            os_log("Replaced snapshot with USDZ render: %@", log: OSLog.default, type: .info, snapshotURL.path)
                        }
                        
                        DispatchQueue.main.async {
                            self.statusLabel.text = "Model loaded successfully."
                            self.downloadedFileURL = usdzURL
                            self.downloadButton.isHidden = false
                            self.shareButton.isHidden = false
                            self.channel?.invokeMethod("processingComplete", arguments: ["usdzPath": usdzURL.path]) { result in
                                if let error = result as? FlutterError {
                                    os_log("Failed to invoke processingComplete: %@", log: OSLog.default, type: .error, error.message ?? "Unknown error")
                                }
                            }
                            completion(.success(usdzURL, totalSize))
                        }
                    } catch {
                        os_log("Failed to load USDZ in SCNView, falling back to QLPreview: %@", log: OSLog.default, type: .error, error.localizedDescription)
                        let previewController = QLPreviewController()
                        previewController.dataSource = self
                        self.present(previewController, animated: true) {
                            // Capture snapshot from SCNView (since QLPreviewController doesn’t provide direct snapshot API)
                            // This captures the last SCNView state; alternatively, we rely on the pre-processed snapshot
                            let snapshot = self.sceneView.snapshot()
                            var snapshotURL = scanFolderURL.appendingPathComponent("snapshot.png")
                            if let data = snapshot.pngData() {
                                try? data.write(to: snapshotURL)
                                try? snapshotURL.setResourceValues(resourceValues)
                                os_log("Replaced snapshot for QLPreview: %@", log: OSLog.default, type: .info, snapshotURL.path)
                            }
                            
                            self.statusLabel.text = "Model loaded in Quick Look."
                            self.downloadedFileURL = usdzURL
                            self.downloadButton.isHidden = false
                            self.shareButton.isHidden = false
                            self.channel?.invokeMethod("processingComplete", arguments: ["usdzPath": usdzURL.path]) { result in
                                if let error = result as? FlutterError {
                                    os_log("Failed to invoke processingComplete: %@", log: OSLog.default, type: .error, error.message ?? "Unknown error")
                                }
                            }
                            completion(.success(usdzURL, totalSize))
                        }
                    }
                } else {
                    os_log("❌ Invalid USDZ file format", log: OSLog.default, type: .error)
                    try? fileManager.removeItem(at: usdzURL)
                    completion(.failure(FlutterError(
                        code: "INVALID_USDZ",
                        message: "Invalid USDZ file format",
                        details: ["modelUrl": modelUrl.absoluteString]
                    ), modelUrl))
                }
            } catch {
                os_log("❌ Failed to move temporary file or update metadata: %@", log: OSLog.default, type: .error, error.localizedDescription)
                try? fileManager.removeItem(at: usdzURL)
                completion(.failure(FlutterError(
                    code: "SAVE_FAILED",
                    message: "Failed to process downloaded file or update metadata: \(error.localizedDescription)",
                    details: ["modelUrl": modelUrl.absoluteString]
                ), modelUrl))
            }
        }
        task.resume()
    }
    
    @objc private func downloadTapped() {
        guard let usdzURL = downloadedFileURL else {
            showErrorAlert(message: "No USDZ file available to download.")
            return
        }
        
        let documentPicker = UIDocumentPickerViewController(url: usdzURL, in: .exportToService)
        documentPicker.delegate = self
        documentPicker.modalPresentationStyle = .formSheet
        present(documentPicker, animated: true)
        generateHapticFeedback()
    }
    
    @objc private func shareTapped() {
        guard let usdzURL = downloadedFileURL else {
            showErrorAlert(message: "No USDZ file available to share.")
            return
        }
        
        let activityController = UIActivityViewController(activityItems: [usdzURL], applicationActivities: nil)
        activityController.completionWithItemsHandler = { [weak self] _, completed, _, error in
            if completed {
                self?.statusLabel.text = "Model shared successfully."
            } else if let error = error {
                self?.showErrorAlert(message: "Failed to share model: \(error.localizedDescription)")
            }
        }
        present(activityController, animated: true)
        generateHapticFeedback()
    }
    
    @objc private func closeTapped() {
        channel?.invokeMethod("closeARModule", arguments: nil) { result in
            if let error = result as? FlutterError {
                os_log("Failed to invoke closeARModule: %@", log: OSLog.default, type: .error, error.message ?? "Unknown error")
            }
        }
        DispatchQueue.main.async {
            var presentingVC = self.presentingViewController
            while let parent = presentingVC?.presentingViewController {
                presentingVC = parent
            }
            presentingVC?.dismiss(animated: true, completion: nil)
        }
    }
    
    @objc private func backTapped() {
        dismiss(animated: true, completion: nil)
    }
    
    private func showErrorAlert(message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
        generateHapticFeedback(.error)
    }
    
    private func showErrorAlertWithLink(message: String) {
        let alert = UIAlertController(
            title: "Error",
            message: "\(message)\n\nYou can download the model directly from the browser.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Open in Browser", style: .default) { _ in
            if let url = self.modelUrl {
                UIApplication.shared.open(url, options: [:])
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
        generateHapticFeedback(.error)
    }
    
    private func validateUSDZFile(at url: URL) throws -> Bool {
        let fileManager = FileManager.default
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? Int64, fileSize > 0 else {
            return false
        }
        
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try SSZipArchive.unzipFile(atPath: url.path, toDestination: tempDir.path)
            try fileManager.removeItem(at: tempDir)
            return true
        } catch {
            os_log("❌ USDZ validation failed: %@", log: OSLog.default, type: .error, error.localizedDescription)
            return false
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    private func generateHapticFeedback(_ type: UINotificationFeedbackGenerator.FeedbackType = .success) {
        let feedbackGenerator = UINotificationFeedbackGenerator()
        feedbackGenerator.prepare()
        feedbackGenerator.notificationOccurred(type)
    }
    
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return downloadedFileURL != nil ? 1 : 0
    }
    
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return downloadedFileURL! as NSURL
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        statusLabel.text = "Model saved successfully."
        generateHapticFeedback()
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        statusLabel.text = "Download cancelled."
    }
    
    private func updateScanStatus(to status: String, for url: URL) {
        let success = ScanLocalStorage.shared.updateScanStatus(status, for: url)
        if !success {
            os_log("⚠️ Failed to update scan status to %@", log: OSLog.default, type: .error, status)
        }
    }
}
@available(iOS 13.4, *)
protocol ControlPanelDelegate: AnyObject {
    func controlPanelDidTapStart(_ controlPanel: ControlPanel)
    func controlPanelDidTapStop(_ controlPanel: ControlPanel)
}

@available(iOS 13.4, *)
class ControlPanel: UIView {
    private let statusLabel = UILabel()
    private let durationLabel = UILabel() // New label for duration
    private let startButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
    private let stackView = UIStackView()
    weak var delegate: ControlPanelDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.5)
        layer.cornerRadius = 10
        translatesAutoresizingMaskIntoConstraints = false

        statusLabel.text = "Ready to scan"
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        durationLabel.text = "Duration: 00:00"
        durationLabel.textColor = .white
        durationLabel.font = .systemFont(ofSize: 14)
        durationLabel.textAlignment = .center
        durationLabel.translatesAutoresizingMaskIntoConstraints = false

        startButton.setTitle("Start", for: .normal)
        startButton.tintColor = .white
        startButton.backgroundColor = .systemBlue
        startButton.layer.cornerRadius = 8
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        startButton.translatesAutoresizingMaskIntoConstraints = false

        stopButton.setTitle("Stop", for: .normal)
        stopButton.tintColor = .white
        stopButton.backgroundColor = .systemRed
        stopButton.layer.cornerRadius = 8
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        stopButton.translatesAutoresizingMaskIntoConstraints = false

        stackView.axis = .horizontal
        stackView.spacing = 20
        stackView.distribution = .fillEqually
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(startButton)
        stackView.addArrangedSubview(stopButton)

        addSubview(statusLabel)
        addSubview(durationLabel)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            durationLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 5),
            durationLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            stackView.topAnchor.constraint(equalTo: durationLabel.bottomAnchor, constant: 10),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            startButton.heightAnchor.constraint(equalToConstant: 44),
            stopButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    func updateStatus(_ status: String) {
        statusLabel.text = status
    }

    func updateDuration(_ duration: Double) {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        durationLabel.text = String(format: "Duration: %02d:%02d", minutes, seconds)
    }

    func updateUIForScanningState(isScanning: Bool, hasMeshes: Bool) {
        startButton.isEnabled = !isScanning
        stopButton.isEnabled = isScanning
        if !isScanning {
            durationLabel.text = "Duration: 00:00"
        }
    }

    @objc private func startTapped() {
        delegate?.controlPanelDidTapStart(self)
    }

    @objc private func stopTapped() {
        delegate?.controlPanelDidTapStop(self)
    }
}

// MARK: - LocationManager
class LocationManager: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    var latestLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        latestLocation = locations.last
    }
}

// MARK: - CapturedMesh
struct CapturedMesh: Codable {
    var vertices: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
    var indices: [UInt32]
    var transform: [[Float]]
    
    init(vertices: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32], transform: simd_float4x4) {
        self.vertices = vertices
        self.normals = normals
        self.indices = indices
        // Convert simd_float4x4 to [[Float]] for Codable compliance
        self.transform = [
            [transform[0][0], transform[0][1], transform[0][2], transform[0][3]],
            [transform[1][0], transform[1][1], transform[1][2], transform[1][3]],
            [transform[2][0], transform[2][1], transform[2][2], transform[2][3]],
            [transform[3][0], transform[3][1], transform[3][2], transform[3][3]]
        ]
    }
    
    func exportAsPLY() -> String {
        var plyContent = """
        ply
        format ascii 1.0
        element vertex \(vertices.count)
        property float x
        property float y
        property float z
        property float nx
        property float ny
        property float nz
        element face \(indices.count / 3)
        property list uchar uint vertex_indices
        end_header
        """
        
        // Add vertices and normals
        for i in 0..<vertices.count {
            let vertex = vertices[i]
            let normal = normals[i]
            plyContent += "\n\(vertex.x) \(vertex.y) \(vertex.z) \(normal.x) \(normal.y) \(normal.z)"
        }
        
        // Add faces
        for i in stride(from: 0, to: indices.count, by: 3) {
            plyContent += "\n3 \(indices[i]) \(indices[i+1]) \(indices[i+2])"
        }
        
        return plyContent
    }
}
