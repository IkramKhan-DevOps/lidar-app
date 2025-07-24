import UIKit
import Flutter
import os.log
import ARKit
import QuickLook
import UniformTypeIdentifiers
import SwiftUI

@available(iOS 13.4, *)
@main
@objc class AppDelegate: FlutterAppDelegate, QLPreviewControllerDataSource, UIDocumentPickerDelegate {
    private var channel: FlutterMethodChannel?
    private var currentUSDZURL: URL?
    private var openFolderResult: FlutterResult?
    private var modelVC: ModelViewController? // Retain ModelViewController during processing
    private var scanCache: [(url: URL, metadata: ScanMetadata?)]? // Cache for getSavedScans

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        guard let controller = window?.rootViewController as? FlutterViewController else {
            fatalError("Root view controller must be FlutterViewController")
        }

        channel = FlutterMethodChannel(
            name: "com.demo.channel/message",
            binaryMessenger: controller.binaryMessenger
        )

        channel?.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            guard let self = self else {
                result(FlutterError(
                    code: "INSTANCE_DEALLOCATED",
                    message: "AppDelegate was deallocated.",
                    details: nil
                ))
                return
            }

            if #available(iOS 13.4, *) {
                switch call.method {
                case "startScan":
                    self.startLiDARScan(result: result)
                case "getSavedScans":
                    self.getSavedScans(result: result)
                case "deleteScan":
                    self.deleteScan(call: call, result: result)
                case "openUSDZ":
                    self.openUSDZ(call: call, result: result)
                case "shareUSDZ":
                    self.shareUSDZ(call: call, result: result)
                case "closeARModule":
                    result("AR Module closed")
                case "getScanImages":
                    self.getScanImages(call: call, result: result)
                case "openFolder":
                    if #available(iOS 14.0, *) {
                        self.openFolder(call: call, result: result)
                    } else {
                        result(FlutterError(
                            code: "UNSUPPORTED_IOS_VERSION",
                            message: "Folder opening requires iOS 14.0 or later.",
                            details: nil
                        ))
                    }
                case "processScan":
                    self.processScan(call: call, result: result)
                case "updateScanName":
                    self.updateScanName(call: call, result: result)
                case "updateScanStatus":
                    self.updateScanStatus(call: call, result: result)
                case "getZipSize":
                    self.getZipSize(call: call, result: result)
                case "getScanMetadata":
                    self.getScanMetadata(call: call, result: result)
                case "showUSDZCard":
                    self.showUSDZCard(call: call, result: result)
                case "checkZipFile":
                    self.checkZipFile(call: call, result: result)
                default:
                    result(FlutterMethodNotImplemented)
                }
            } else {
                result(FlutterError(
                    code: "UNSUPPORTED_IOS_VERSION",
                    message: "This app requires iOS 13.4 or later for AR functionality.",
                    details: nil
                ))
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func showUSDZCard(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGUMENT",
                message: "Invalid or missing USDZ path.",
                details: nil
            ))
            return
        }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            result(FlutterError(
                code: "FILE_NOT_FOUND",
                message: "USDZ file not found at \(url.path)",
                details: nil
            ))
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let controller = self.window?.rootViewController else {
                result(FlutterError(
                    code: "CONTROLLER_NOT_FOUND",
                    message: "Failed to access root view controller.",
                    details: nil
                ))
                return
            }

            let previewController = QLPreviewController()
            previewController.dataSource = self
            self.currentUSDZURL = url
            controller.present(previewController, animated: true) {
                result("USDZ card view opened for path: \(path)")
            }
        }
    }

    private func getScanMetadata(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let folderPath = args["folderPath"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGUMENT",
                message: "Invalid or missing folder path.",
                details: nil
            ))
            return
        }

        let folderURL = URL(fileURLWithPath: folderPath)
        let metadataURL = folderURL.appendingPathComponent("metadata.json")
        let fileManager = FileManager.default

        do {
            if fileManager.fileExists(atPath: metadataURL.path) {
                let data = try Data(contentsOf: metadataURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let metadata = try decoder.decode(ScanMetadata.self, from: data)
                let dateFormatter = ISO8601DateFormatter()
                let usdzURL = folderURL.appendingPathComponent("model.usdz")
                let hasUsdz = fileManager.fileExists(atPath: usdzURL.path)
                // Validate coordinates
                let validCoordinates = metadata.coordinates?.filter { coord in
                    guard coord.count == 2 else { return false }
                    let lat = coord[0], lon = coord[1]
                    return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180
                } ?? []
                let resultData: [String: Any] = [
                    "scan_id": metadata.scanID,
                    "name": metadata.name,
                    "timestamp": dateFormatter.string(from: metadata.timestamp),
                    "location_name": metadata.locationName ?? "",
                    "coordinates": validCoordinates,
                    "coordinateTimestamps": metadata.coordinateTimestamps ?? [],
                    "image_count": metadata.imageCount,
                    "model_size_bytes": metadata.modelSizeBytes ?? 0,
                    "status": metadata.status,
                    "hasUSDZ": hasUsdz,
                    "duration_seconds": metadata.durationSeconds ?? 0.0
                ]
                os_log("Fetched metadata for %@: %@", log: OSLog.default, type: .info, folderPath, String(describing: resultData))
                result(resultData)
            } else {
                result(FlutterError(
                    code: "METADATA_NOT_FOUND",
                    message: "Metadata file not found at \(metadataURL.path)",
                    details: nil
                ))
            }
        } catch {
            os_log("Failed to fetch metadata for %@: %@", log: OSLog.default, type: .error, folderPath, error.localizedDescription)
            result(FlutterError(
                code: "METADATA_ERROR",
                message: "Failed to read metadata: \(error.localizedDescription)",
                details: nil
            ))
        }
    }

    private func startLiDARScan(result: @escaping FlutterResult) {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            result(FlutterError(
                code: "DEVICE_NOT_SUPPORTED",
                message: "This device does not support LiDAR scanning.",
                details: nil
            ))
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let controller = self.window?.rootViewController as? FlutterViewController else {
                result(FlutterError(
                    code: "CONTROLLER_NOT_FOUND",
                    message: "Failed to access FlutterViewController.",
                    details: nil
                ))
                return
            }

            let scanVC = ScanViewController()
            scanVC.modalPresentationStyle = .fullScreen
            controller.present(scanVC, animated: true) {
                result("Scan started")
            }
        }
    }

    private func getSavedScans(result: @escaping FlutterResult) {
        if let cachedScans = scanCache {
            let dateFormatter = ISO8601DateFormatter()
            let scansData: [[String: Any]] = cachedScans.compactMap { scan in
                guard let metadata = scan.metadata else { return nil }
                let validCoordinates = metadata.coordinates?.filter { coord in
                    guard coord.count == 2 else { return false }
                    let lat = coord[0], lon = coord[1]
                    return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180
                } ?? []
                return [
                    "scanID": metadata.scanID,
                    "name": metadata.name,
                    "folderPath": scan.url.path,
                    "hasUSDZ": ScanLocalStorage.shared.hasUSDZModel(in: scan.url),
                    "usdzPath": scan.url.appendingPathComponent("model.usdz").path,
                    "timestamp": dateFormatter.string(from: metadata.timestamp),
                    "coordinates": validCoordinates,
                    "coordinateTimestamps": metadata.coordinateTimestamps ?? [],
                    "locationName": metadata.locationName ?? "",
                    "modelSizeBytes": metadata.modelSizeBytes ?? 0,
                    "imageCount": metadata.imageCount,
                    "status": metadata.status,
                    "snapshotPath": metadata.snapshotPath ?? ""
                ]
            }
            result(["scans": scansData])
            return
        }

        let scans = ScanLocalStorage.shared.getAllScans()
        scanCache = scans // Cache the scans
        let dateFormatter = ISO8601DateFormatter()
        let scansData: [[String: Any]] = scans.compactMap { scan in
            guard let metadata = scan.metadata else { return nil }
            let validCoordinates = metadata.coordinates?.filter { coord in
                guard coord.count == 2 else { return false }
                let lat = coord[0], lon = coord[1]
                return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180
            } ?? []
            return [
                "scanID": metadata.scanID,
                "name": metadata.name,
                "folderPath": scan.url.path,
                "hasUSDZ": ScanLocalStorage.shared.hasUSDZModel(in: scan.url),
                "usdzPath": scan.url.appendingPathComponent("model.usdz").path,
                "timestamp": dateFormatter.string(from: metadata.timestamp),
                "coordinates": validCoordinates,
                "coordinateTimestamps": metadata.coordinateTimestamps ?? [],
                "locationName": metadata.locationName ?? "",
                "modelSizeBytes": metadata.modelSizeBytes ?? 0,
                "imageCount": metadata.imageCount,
                "status": metadata.status,
                "snapshotPath": metadata.snapshotPath ?? ""
            ]
        }
        result(["scans": scansData])
    }

    private func deleteScan(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGUMENT",
                message: "Invalid or missing path.",
                details: nil
            ))
            return
        }

        let url = URL(fileURLWithPath: path)
        let success = ScanLocalStorage.shared.deleteScan(at: url)
        if success {
            invalidateScanCache()
            result("Scan deleted successfully")
        } else {
            result(FlutterError(
                code: "DELETE_FAILED",
                message: "Failed to delete scan.",
                details: nil
            ))
        }
    }

    private func openUSDZ(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGUMENT",
                message: "Invalid or missing USDZ path.",
                details: nil
            ))
            return
        }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            result(FlutterError(
                code: "FILE_NOT_FOUND",
                message: "USDZ file not found at \(url.path)",
                details: nil
            ))
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let controller = self.window?.rootViewController else {
                result(FlutterError(
                    code: "CONTROLLER_NOT_FOUND",
                    message: "Failed to access root view controller.",
                    details: nil
                ))
                return
            }

            let previewController = QLPreviewController()
            previewController.dataSource = self
            self.currentUSDZURL = url
            controller.present(previewController, animated: true) {
                result("USDZ preview opened")
            }
        }
    }

    private func shareUSDZ(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGUMENT",
                message: "Invalid or missing USDZ path.",
                details: nil
            ))
            return
        }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            result(FlutterError(
                code: "FILE_NOT_FOUND",
                message: "USDZ file not found at \(url.path)",
                details: nil
            ))
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let controller = self.window?.rootViewController else {
                result(FlutterError(
                    code: "CONTROLLER_NOT_FOUND",
                    message: "Failed to access root view controller.",
                    details: nil
                ))
                return
            }

            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activityVC.completionWithItemsHandler = { _, completed, _, error in
                if completed {
                    result("USDZ shared successfully")
                } else if let error = error {
                    result(FlutterError(
                        code: "SHARE_FAILED",
                        message: "Failed to share USDZ: \(error.localizedDescription)",
                        details: nil
                    ))
                } else {
                    result("Share cancelled")
                }
            }
            controller.present(activityVC, animated: true)
        }
    }

    private func getScanImages(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let folderPath = args["folderPath"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGUMENT",
                message: "Invalid or missing folder path.",
                details: nil
            ))
            return
        }

        if let imagePaths = ScanLocalStorage.shared.getScanImages(folderPath: folderPath) {
            result(imagePaths)
        } else {
            result(FlutterError(
                code: "FETCH_IMAGES_FAILED",
                message: "Failed to fetch images for folder: \(folderPath)",
                details: nil
            ))
        }
    }

    @available(iOS 14.0, *)
    private func openFolder(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGUMENT",
                message: "Invalid or missing folder path.",
                details: nil
            ))
            return
        }

        let folderURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: folderURL.path) else {
            result(FlutterError(
                code: "FOLDER_NOT_FOUND",
                message: "Folder does not exist: \(folderURL.path)",
                details: nil
            ))
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let controller = self.window?.rootViewController else {
                result(FlutterError(
                    code: "CONTROLLER_NOT_FOUND",
                    message: "Failed to access root view controller.",
                    details: nil
                ))
                return
            }

            self.openFolderResult = result
            let documentPicker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.folder],
                asCopy: false
            )
            documentPicker.delegate = self
            documentPicker.directoryURL = folderURL
            controller.present(documentPicker, animated: true)
        }
    }

    private func getZipSize(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let folderPath = args["folderPath"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGUMENT",
                message: "Invalid or missing folder path.",
                details: nil
            ))
            return
        }

        let scanFolderURL = URL(fileURLWithPath: folderPath)
        let zipURL = scanFolderURL.appendingPathComponent("input_data.zip")
        let fileManager = FileManager.default

        do {
            guard fileManager.fileExists(atPath: zipURL.path) else {
                throw NSError(domain: "FileError", code: -1, userInfo: [NSLocalizedDescriptionKey: "ZIP file not found at \(zipURL.path)"])
            }
            let zipAttributes = try fileManager.attributesOfItem(atPath: zipURL.path)
            let zipSizeBytes = zipAttributes[.size] as? Int64 ?? 0
            result(["zipSizeBytes": zipSizeBytes])
        } catch {
            os_log("❌ Failed to get ZIP file size: %@", log: OSLog.default, type: .error, error.localizedDescription)
            result(FlutterError(
                code: "FILE_ERROR",
                message: "Failed to get ZIP file size: \(error.localizedDescription)",
                details: nil
            ))
        }
    }

    private func checkZipFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let folderPath = args["folderPath"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGUMENT",
                message: "Invalid or missing folder path.",
                details: nil
            ))
            return
        }

        let zipURL = URL(fileURLWithPath: folderPath).appendingPathComponent("input_data.zip")
        let exists = FileManager.default.fileExists(atPath: zipURL.path)
        result(["exists": exists])
    }

    private func updateScanStatus(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let folderPath = args["folderPath"] as? String,
              let status = args["status"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGUMENT",
                message: "Invalid or missing folder path or status.",
                details: nil
            ))
            return
        }

        let folderURL = URL(fileURLWithPath: folderPath)
        let success = ScanLocalStorage.shared.updateScanStatus(status, for: folderURL)
        if success {
            invalidateScanCache()
            os_log("Updated scan status to %@ for: %@", log: OSLog.default, type: .info, status, folderPath)
            result("Scan status updated successfully")
        } else {
            os_log("Failed to update scan status to %@ for: %@", log: OSLog.default, type: .error, status, folderPath)
            result(FlutterError(
                code: "UPDATE_STATUS_FAILED",
                message: "Failed to update scan status.",
                details: nil
            ))
        }
    }

    private func processScan(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let folderPath = args["folderPath"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGUMENT",
                message: "Invalid or missing folder path.",
                details: nil
            ))
            return
        }

        let scanFolderURL = URL(fileURLWithPath: folderPath)
        let zipURL = scanFolderURL.appendingPathComponent("input_data.zip")
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: zipURL.path) else {
            os_log("ZIP file not found at: %@", log: OSLog.default, type: .error, zipURL.path)
            result(FlutterError(
                code: "FILE_NOT_FOUND",
                message: "ZIP file not found at \(zipURL.path)",
                details: nil
            ))
            return
        }

        // Retain ModelViewController
        self.modelVC = ModelViewController()
        guard let modelVC = self.modelVC else {
            result(FlutterError(
                code: "CONTROLLER_INIT_FAILED",
                message: "Failed to initialize ModelViewController.",
                details: nil
            ))
            return
        }
        modelVC.currentScanFolderURL = scanFolderURL

        var backgroundTask: UIBackgroundTaskIdentifier = .invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            os_log("⚠️ Background task expired for processScan", log: OSLog.default, type: .error)
            self?.modelVC = nil
            result(FlutterError(
                code: "BACKGROUND_TASK_EXPIRED",
                message: "Processing timed out due to app suspension.",
                details: nil
            ))
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        }

        // Notify Flutter that processing has started
        channel?.invokeMethod("updateProcessingStatus", arguments: ["status": "processing"]) { error in
            if let error = error {
                os_log("Failed to notify Flutter of processing start: %@", log: OSLog.default, type: .error, (error as AnyObject).localizedDescription)
            }
        }

        // Add timeout for processing
        let timeout: TimeInterval = 300 // 5 minutes
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let timeoutDate = Date().addingTimeInterval(timeout)
            modelVC.processZipFile(at: zipURL) { [weak self] processResult in
                guard let self = self else { return }
                defer { self.modelVC = nil } // Release after completion

                if Date() > timeoutDate {
                    os_log("⚠️ Processing timed out after %f seconds", log: OSLog.default, type: .error, timeout)
                    result(FlutterError(
                        code: "PROCESSING_TIMEOUT",
                        message: "Processing took too long and was terminated.",
                        details: nil
                    ))
                    if backgroundTask != .invalid {
                        UIApplication.shared.endBackgroundTask(backgroundTask)
                        backgroundTask = .invalid
                    }
                    return
                }

                switch processResult {
                case .success(let usdzURL, let modelSizeBytes):
                    os_log("✅ Successfully processed and saved USDZ model at: %@", log: OSLog.default, type: .info, usdzURL.path)
                    let success = ScanLocalStorage.shared.updateScanStatus("uploaded", for: scanFolderURL)
                    if !success {
                        os_log("⚠️ Failed to update scan status to uploaded", log: OSLog.default, type: .error)
                    }
                    self.invalidateScanCache()
                    result([
                        "usdzPath": usdzURL.path,
                        "modelSizeBytes": modelSizeBytes
                    ])
                case .failure(let error, let modelUrl):
                    os_log("❌ Failed to process scan: %@", log: OSLog.default, type: .error, error.message ?? "Unknown error")
                    let success = ScanLocalStorage.shared.updateScanStatus("failed", for: scanFolderURL)
                    if !success {
                        os_log("⚠️ Failed to update scan status to failed", log: OSLog.default, type: .error)
                    }
                    self.invalidateScanCache()
                    result(FlutterError(
                        code: error.code,
                        message: error.message,
                        details: ["modelUrl": modelUrl?.absoluteString ?? ""]
                    ))
                }

                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                    backgroundTask = .invalid
                }
            }
        }
    }

    private func updateScanName(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let folderPath = args["folderPath"] as? String,
              let name = args["name"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGUMENT",
                message: "Invalid or missing folder path or name.",
                details: nil
            ))
            return
        }

        let folderURL = URL(fileURLWithPath: folderPath)
        let success = ScanLocalStorage.shared.updateScanName(name, for: folderURL)
        if success {
            invalidateScanCache()
            os_log("Updated scan name to %@ for: %@", log: OSLog.default, type: .info, name, folderPath)
            result("Scan name updated successfully")
        } else {
            os_log("Failed to update scan name for: %@", log: OSLog.default, type: .error, folderPath)
            result(FlutterError(
                code: "UPDATE_NAME_FAILED",
                message: "Failed to update scan name.",
                details: nil
            ))
        }
    }

    private func invalidateScanCache() {
        scanCache = nil
        os_log("Invalidated scan cache", log: OSLog.default, type: .info)
    }

    // MARK: - QLPreviewControllerDataSource
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return currentUSDZURL != nil ? 1 : 0
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return currentUSDZURL! as QLPreviewItem
    }

    // MARK: - UIDocumentPickerDelegate
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        openFolderResult?("Folder opened successfully")
        openFolderResult = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        openFolderResult?("Folder open cancelled")
        openFolderResult = nil
    }
}
