import UIKit
import Flutter
import os.log
import ARKit
import QuickLook
import UniformTypeIdentifiers


@available(iOS 13.4, *)
@main
@objc class AppDelegate: FlutterAppDelegate, QLPreviewControllerDataSource, UIDocumentPickerDelegate {
    private var channel: FlutterMethodChannel?
    private var currentUSDZURL: URL?
    private var openFolderResult: FlutterResult?

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
            guard let self = self else { return }

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
                    // Fallback on earlier versions
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
        let scans = ScanLocalStorage.shared.getAllScans()
        let dateFormatter = ISO8601DateFormatter()
        let scanData: [[String: Any]] = scans.compactMap { scan in
            guard let metadata = scan.metadata else { return nil }
            let usdzURL = ScanLocalStorage.shared.hasUSDZModel(in: scan.url) ? scan.url.appendingPathComponent("model.usdz") : nil
            let data = [
                "scanID": metadata.scanID,
                "name": metadata.name,
                "usdzPath": usdzURL?.path as Any,
                "folderPath": scan.url.path,
                "hasUSDZ": usdzURL != nil,
                "timestamp": dateFormatter.string(from: metadata.timestamp),
                "coordinates": metadata.coordinates ?? [],
                "locationName": metadata.locationName ?? "",
                "modelSizeBytes": metadata.modelSizeBytes ?? 0,
                "imageCount": metadata.imageCount
            ]
            os_log("Scan data: %@", log: OSLog.default, type: .info, String(describing: data))
            return data
        }
        result(scanData)
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let controller = self.window?.rootViewController else {
                result(FlutterError(
                    code: "CONTROLLER_NOT_FOUND",
                    message: "Failed to access root view controller.",
                    details: nil
                ))
                return
            }

            if !FileManager.default.fileExists(atPath: folderURL.path) {
                result(FlutterError(
                    code: "FOLDER_NOT_FOUND",
                    message: "Folder does not exist: \(folderURL.path)",
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
