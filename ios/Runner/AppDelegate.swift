import UIKit
import os.log
import ARKit
import QuickLook
import UniformTypeIdentifiers
import Network
import GoogleMaps

@available(iOS 13.4, *)
@main
@objc class AppDelegate: FlutterAppDelegate, QLPreviewControllerDataSource, UIDocumentPickerDelegate {
    private var channel: FlutterMethodChannel?
    private var currentUSDZURL: URL?
    private var openFolderResult: FlutterResult?
    private var modelVC: ModelViewController?
    private var scanViewController: ScanViewController? // Strong reference to prevent deallocation
    private var scanCache: [(url: URL, metadata: ScanMetadata?)]?
    private let networkMonitor = NWPathMonitor()
    private var isOnline = false
    private let apiBaseURL = "http://192.168.1.20:9000/api/v1" // Your API base URL
    // Processing API URL function
    private func processAPIURL(scanId: Int) -> String {
        return "http://192.168.1.20:9000/api/v1/scans/\(scanId)/process/"
    }
    private var autoSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "auto_sync_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "auto_sync_enabled") }
    }
    
    private func readAuthToken() -> String? {
        // Try common shared_preferences storage patterns
        if let v = UserDefaults.standard.string(forKey: "auth_token") { return v }
        if let v = UserDefaults.standard.string(forKey: "flutter.auth_token") { return v }
        if let v = UserDefaults(suiteName: "flutter")?.string(forKey: "auth_token") { return v }
        if let v = UserDefaults(suiteName: "flutter")?.string(forKey: "flutter.auth_token") { return v }
        return nil
    }

 override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        guard let controller = window?.rootViewController as? FlutterViewController else {
            fatalError("Root view controller must be FlutterViewController")
        }
        // Register Flutter plugins
        GeneratedPluginRegistrant.register(with: self)

        // Initialize Google Maps SDK
        if let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let apiKey = plist["GMSApiKey"] as? String {
            GMSServices.provideAPIKey(apiKey)
            os_log("✅ [GOOGLE MAPS] Initialized with API key", log: OSLog.default, type: .info)
        } else {
            os_log("❌ [GOOGLE MAPS] Failed to find API key in Info.plist", log: OSLog.default, type: .error)
        }

        // Set up your existing method channel
        channel = FlutterMethodChannel(
            name: "com.demo.channel/message",
            binaryMessenger: controller.binaryMessenger
        )

        channel?.setMethodCallHandler { [weak self] call, result in
            guard let self = self else {
                result(FlutterError(
                    code: "INSTANCE_DEALLOCATED",
                    message: "AppDelegate was deallocated.",
                    details: nil
                ))
                return
            }

            // Add debug logging for all method calls
            os_log("🔍 [METHOD CHANNEL] Received method call: %@ with arguments: %@", log: OSLog.default, type: .info, call.method, String(describing: call.arguments))

            // Add your method call handling logic here
            switch call.method {
            // Non-AR methods that work on all iOS versions
            case "getSavedScans":
                self.getSavedScans(result: result)
            case "deleteScan":
                self.deleteScan(call: call, result: result)
            case "getScanImages":
                self.getScanImages(call: call, result: result)
            case "updateScanName":
                self.updateScanName(call: call, result: result)
            case "updateScanStatus":
                self.updateScanStatus(call: call, result: result)
            case "getZipSize":
                self.getZipSize(call: call, result: result)
            case "getScanMetadata":
                self.getScanMetadata(call: call, result: result)
            case "checkZipFile":
                self.checkZipFile(call: call, result: result)
            case "scanComplete":
                self.handleScanComplete(call: call, result: result)
            case "uploadScanToBackend":
                self.handleUploadScanToBackend(call: call, result: result)
            case "downloadZipFile":
                self.downloadZipFile(call: call, result: result)
            case "clearAllLocalData":
                self.clearAllLocalData(call: call, result: result)
            case "setAutoSyncEnabled":
                self.setAutoSyncEnabled(call: call, result: result)
            case "getAutoSyncEnabled":
                self.getAutoSyncEnabled(result: result)
            case "syncInitializedScans":
                self.syncInitializedScans(result: result)
            case "processModelOnServer":
                self.processModelOnServer(call: call, result: result)
            // AR and iOS version-specific methods
            case "startScan":
                if #available(iOS 13.4, *) {
                    self.startLiDARScan(result: result)
                } else {
                    result(FlutterError(
                        code: "UNSUPPORTED_IOS_VERSION",
                        message: "LiDAR scanning requires iOS 13.4 or later.",
                        details: nil
                    ))
                }
            case "openUSDZ":
                if #available(iOS 13.4, *) {
                    self.openUSDZ(call: call, result: result)
                } else {
                    result(FlutterError(
                        code: "UNSUPPORTED_IOS_VERSION",
                        message: "USDZ preview requires iOS 13.4 or later.",
                        details: nil
                    ))
                }
            case "shareUSDZ":
                if #available(iOS 13.4, *) {
                    self.shareUSDZ(call: call, result: result)
                } else {
                    result(FlutterError(
                        code: "UNSUPPORTED_IOS_VERSION",
                        message: "USDZ sharing requires iOS 13.4 or later.",
                        details: nil
                    ))
                }
            case "closeARModule":
                if #available(iOS 13.4, *) {
                    self.handleCloseARModule(result: result)
                } else {
                    result(FlutterError(
                        code: "UNSUPPORTED_IOS_VERSION",
                        message: "AR module requires iOS 13.4 or later.",
                        details: nil
                    ))
                }
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
                if #available(iOS 13.4, *) {
                    self.processScan(call: call, result: result)
                } else {
                    result(FlutterError(
                        code: "UNSUPPORTED_IOS_VERSION",
                        message: "Scan processing requires iOS 13.4 or later.",
                        details: nil
                    ))
                }
            case "showUSDZCard":
                if #available(iOS 13.4, *) {
                    self.showUSDZCard(call: call, result: result)
                } else {
                    result(FlutterError(
                        code: "UNSUPPORTED_IOS_VERSION",
                        message: "USDZ card display requires iOS 13.4 or later.",
                        details: nil
                    ))
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        setupNetworkMonitor()

        // Add notification observer for upload requests from ScanViewController
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUploadNotification),
            name: NSNotification.Name("UploadScanToBackend"),
            object: nil
        )

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        os_log("⚠️ [MEMORY WARNING] Memory warning received - this might affect method channel", log: OSLog.default, type: .error)
        // Clean up any heavy resources
        invalidateScanCache()
        // Release scan view controller if it exists
        if scanViewController != nil {
            os_log("🧹 [MEMORY WARNING] Releasing scan view controller due to memory pressure", log: OSLog.default, type: .info)
            scanViewController = nil
        }
        // Test method channel after memory warning
        testMethodChannelConnectivity()
    }



    private func setupNetworkMonitor() {
            networkMonitor.pathUpdateHandler = { [weak self] path in
                guard let self = self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = path.status == .satisfied
                
                os_log("📶 [NETWORK] Network status changed: %@", log: OSLog.default, type: .info, self.isOnline ? "ONLINE" : "OFFLINE")
                
                // Notify Flutter about network status change
                DispatchQueue.main.async {
                    self.channel?.invokeMethod("networkStatusChanged", arguments: ["isOnline": self.isOnline])
                }
                
                if self.isOnline && wasOffline {
                    os_log("🔄 [SYNC] Device came back online, checking auto-sync setting...", log: OSLog.default, type: .info)
                    
                    // Only auto-sync if auto-sync is enabled
                    if self.autoSyncEnabled {
                        os_log("🔄 [AUTO SYNC] Auto-sync enabled, starting sync after coming online...", log: OSLog.default, type: .info)
                        
                        // Wait a bit for network to stabilize
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            // First sync pending/failed/processing scans (these always sync regardless of auto-sync setting)
                            self.syncOfflineScansToServer { success in
                                if success {
                                    os_log("✅ [SYNC] All offline scans synced successfully", log: OSLog.default, type: .info)
                                } else {
                                    os_log("❌ [SYNC] Failed to sync some offline scans", log: OSLog.default, type: .error)
                                }
                                
                                // Only sync initialized scans if auto-sync is enabled
                                if self.autoSyncEnabled {
                                    os_log("🔄 [AUTO SYNC] Triggering initialized scans sync...", log: OSLog.default, type: .info)
                                    self.syncInitializedScans { autoSyncSuccess in
                                        if autoSyncSuccess {
                                            os_log("✅ [AUTO SYNC] Auto-sync completed successfully", log: OSLog.default, type: .info)
                                        } else {
                                            os_log("❌ [AUTO SYNC] Auto-sync failed for some scans", log: OSLog.default, type: .error)
                                        }
                                        // Notify Flutter about auto-sync completion
                                        self.channel?.invokeMethod("offlineSyncComplete", arguments: ["success": success && autoSyncSuccess])
                                    }
                                } else {
                                    // Notify Flutter about offline sync completion (but no auto-sync)
                                    self.channel?.invokeMethod("offlineSyncComplete", arguments: ["success": success])
                                }
                            }
                        }
                    } else {
                        os_log("⏸️ [AUTO SYNC] Auto-sync disabled, skipping automatic sync", log: OSLog.default, type: .info)
                        // Still notify Flutter about network change, but don't sync
                        self.channel?.invokeMethod("offlineSyncComplete", arguments: ["success": true, "skipped": true])
                    }
                }
            }
            let queue = DispatchQueue(label: "AppDelegateNetworkMonitor")
            networkMonitor.start(queue: queue)
        }

       // Enhanced offline sync functionality
       private func syncOfflineScansToServer(completion: @escaping (Bool) -> Void) {
           os_log("🔄 [OFFLINE SYNC] Starting offline scans sync...", log: OSLog.default, type: .info)
           
           let localScans = ScanLocalStorage.shared.getAllScans()
           let pendingScans = localScans.filter { scan in
               guard let metadata = scan.metadata else { return false }
               return metadata.status == "pending" || metadata.status == "failed" || metadata.status == "processing"
           }
           
           guard !pendingScans.isEmpty else {
               os_log("ℹ️ [OFFLINE SYNC] No pending scans to sync", log: OSLog.default, type: .info)
               completion(true)
               return
           }
           
           os_log("📜 [OFFLINE SYNC] Found %d pending scans to upload", log: OSLog.default, type: .info, pendingScans.count)
           
           let group = DispatchGroup()
           var syncResults: [(scan: (url: URL, metadata: ScanMetadata?), success: Bool)] = []
           
           for scan in pendingScans {
               guard let metadata = scan.metadata else { continue }
               
               os_log("🚀 [OFFLINE SYNC] Uploading scan: %@", log: OSLog.default, type: .info, metadata.name)
               
               // Update status to uploading
               _ = ScanLocalStorage.shared.updateScanStatus("uploading", for: scan.url)
               
               group.enter()
               self.uploadScan(folderURL: scan.url) { [weak self] success in
                   syncResults.append((scan: scan, success: success))
                   
                   if success {
                       os_log("✅ [OFFLINE SYNC] Successfully uploaded: %@", log: OSLog.default, type: .info, metadata.name)
                       
                       // Keep local data - do not delete after successful upload
                       // Update status to uploaded but preserve local files
                       _ = ScanLocalStorage.shared.updateScanStatus("uploaded", for: scan.url)
                       os_log("📱 [OFFLINE SYNC] Keeping local scan data after successful upload: %@", log: OSLog.default, type: .info, scan.url.path)
                   } else {
                       os_log("❌ [OFFLINE SYNC] Failed to upload: %@", log: OSLog.default, type: .error, metadata.name)
                       
                       // Mark scan as failed for retry later
                       _ = ScanLocalStorage.shared.updateScanStatus("failed", for: scan.url)
                   }
                   
                   group.leave()
               }
           }
           
           group.notify(queue: .main) {
               self.invalidateScanCache()
               
               let successCount = syncResults.filter { $0.success }.count
               let failedCount = syncResults.count - successCount
               
               os_log("📊 [OFFLINE SYNC] Sync completed - Success: %d, Failed: %d", log: OSLog.default, type: .info, successCount, failedCount)
               
               completion(failedCount == 0)
           }
       }
       
       // Legacy method for backwards compatibility
       private func syncLocalToServer(completion: @escaping (Bool) -> Void) {
           syncOfflineScansToServer(completion: completion)
       }

           private func fetchAPIScans(completion: @escaping ([ScanMetadata]?) -> Void) {
                   let url = URL(string: "\(apiBaseURL)/scans/")!
                   let token = readAuthToken()
                   os_log("Fetching API scans from: %@", log: OSLog.default, type: .info, url.absoluteString)
                   os_log("Auth header (masked): Token %@***", log: OSLog.default, type: .info, (token ?? "").prefix(6).description)

                   var request = URLRequest(url: url)
                   request.httpMethod = "GET"
                   request.setValue("application/json", forHTTPHeaderField: "Accept")
                   if let token = token, !token.isEmpty {
                       request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
                   }

                   let task = URLSession.shared.dataTask(with: request) { data, response, error in
                       if let error = error {
                           os_log("Failed to fetch API scans: %@", log: OSLog.default, type: .error, error.localizedDescription)
                           completion(nil)
                           return
                       }
                       guard let data = data, let httpResponse = response as? HTTPURLResponse else {
                           completion(nil)
                           return
                       }
                       if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                           os_log("Scans API unauthorized (%d). Check token header on server.", log: OSLog.default, type: .error, httpResponse.statusCode)
                           completion(nil)
                           return
                       }
                       if httpResponse.statusCode != 200 {
                           os_log("Scans API unexpected status: %d", log: OSLog.default, type: .error, httpResponse.statusCode)
                           completion(nil)
                           return
                       }
                       do {
                            // Server returns an array of scan objects; map to ScanMetadata properly
                            let generic = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
                            let dateFormatter = ISO8601DateFormatter()
                            let mapped: [ScanMetadata] = generic.map { item in
                                let id = (item["id"] as? Int) ?? 0
                                let title = (item["title"] as? String) ?? ""
                                let description = (item["description"] as? String) ?? ""
                                let duration = (item["duration"] as? Double) ?? 0.0
                                let areaCovered = (item["area_covered"] as? Double) ?? 0.0
                                let height = (item["height"] as? Double) ?? 0.0
                                let dataSizeMB = (item["data_size_mb"] as? Double) ?? 0.0
                                let location = (item["location"] as? String) ?? ""
                                let rawStatus = (item["status"] as? String) ?? "pending"
                                let totalImages = (item["total_images"] as? Int) ?? 0
                                let created = (item["created_at"] as? String) ?? ISO8601DateFormatter().string(from: Date())
                                let updated = (item["updated_at"] as? String) ?? created
                                
                                // Normalize status from server to match local statuses
                                let normalizedStatus: String
                                switch rawStatus.lowercased() {
                                case "completed", "processed", "done":
                                    normalizedStatus = "completed"
                                case "failed", "error":
                                    normalizedStatus = "failed"
                                case "uploading", "processing":
                                    normalizedStatus = "processing"
                                case "pending", "queued":
                                    normalizedStatus = "pending"
                                default:
                                    normalizedStatus = rawStatus // Keep original if unknown
                                }
                                
                                let ts = dateFormatter.date(from: created) ?? Date()
                                let modelSizeBytes = Int64(dataSizeMB * 1024 * 1024) // Convert MB to bytes
                                
                                return ScanMetadata(
                                    name: title,
                                    timestamp: ts,
                                    scanID: String(id),
                                    coordinates: nil, // API doesn't provide coordinates yet
                                    coordinateTimestamps: nil,
                                    locationName: location.isEmpty ? nil : location,
                                    modelSizeBytes: modelSizeBytes > 0 ? modelSizeBytes : nil,
                                    imageCount: totalImages,
                                    status: normalizedStatus,
                                    snapshotPath: nil, // API doesn't provide snapshot path yet
                                    durationSeconds: duration,
                                    boundsSize: "[\(areaCovered), 0.0, \(height)]" // area_covered as width, height as height
                                )
                            }
                            completion(mapped)
                        } catch {
                            os_log("Failed to parse API scans (mapping): %@", log: OSLog.default, type: .error, error.localizedDescription)
                            completion(nil)
                        }
                   }
                   task.resume()
               }
    private func downloadZipFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
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

        // Copy zip file to temporary directory to ensure shareability
        let tempDir = FileManager.default.temporaryDirectory
        let tempZipURL = tempDir.appendingPathComponent("input_data_\(UUID().uuidString).zip")
        do {
            if fileManager.fileExists(atPath: tempZipURL.path) {
                try fileManager.removeItem(at: tempZipURL)
            }
            try fileManager.copyItem(at: zipURL, to: tempZipURL)
            os_log("Copied ZIP file to temporary directory: %@", log: OSLog.default, type: .info, tempZipURL.path)
        } catch {
            os_log("Failed to copy ZIP file to temporary directory: %@", log: OSLog.default, type: .error, error.localizedDescription)
            result(FlutterError(
                code: "FILE_COPY_FAILED",
                message: "Failed to prepare ZIP file for download: \(error.localizedDescription)",
                details: nil
            ))
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let controller = self.window?.rootViewController else {
                // Clean up temporary file
                try? fileManager.removeItem(at: tempZipURL)
                result(FlutterError(
                    code: "CONTROLLER_NOT_FOUND",
                    message: "Failed to access root view controller.",
                    details: nil
                ))
                return
            }

            let activityVC = UIActivityViewController(activityItems: [tempZipURL], applicationActivities: nil)
            // Configure for iPad to avoid UIPopoverPresentationController crash
            if UIDevice.current.userInterfaceIdiom == .pad {
                activityVC.popoverPresentationController?.sourceView = controller.view
                activityVC.popoverPresentationController?.sourceRect = CGRect(
                    x: controller.view.bounds.midX,
                    y: controller.view.bounds.midY,
                    width: 0,
                    height: 0
                )
                activityVC.popoverPresentationController?.permittedArrowDirections = []
            }

            activityVC.completionWithItemsHandler = { _, completed, _, error in
                // Clean up temporary file
                try? fileManager.removeItem(at: tempZipURL)
                if completed {
                    os_log("ZIP file shared successfully: %@", log: OSLog.default, type: .info, tempZipURL.path)
                    result("Zip file downloaded successfully")
                } else if let error = error {
                    os_log("Failed to share ZIP file: %@", log: OSLog.default, type: .error, error.localizedDescription)
                    result(FlutterError(
                        code: "DOWNLOAD_FAILED",
                        message: "Failed to download ZIP file: \(error.localizedDescription)",
                        details: nil
                    ))
                } else {
                    os_log("ZIP file download cancelled: %@", log: OSLog.default, type: .info, tempZipURL.path)
                    result("Download cancelled")
                }
            }
            controller.present(activityVC, animated: true)
        }
    }

    private func handleScanComplete(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let folderPath = args["folderPath"] as? String else {
            os_log("❌ [SCAN COMPLETE] Invalid arguments: %@", log: OSLog.default, type: .error, String(describing: call.arguments))
            result(FlutterError(
                code: "INVALID_ARGUMENT",
                message: "Invalid or missing folder path in scanComplete.",
                details: nil
            ))
            return
        }

        os_log("✅ [SCAN COMPLETE] Starting - Method channel active: %@", log: OSLog.default, type: .info, self.channel != nil ? "YES" : "NO")
        
        // Invalidate cache to ensure fresh scan data
        invalidateScanCache()
        
        let folderURL = URL(fileURLWithPath: folderPath)
        let metaURL = folderURL.appendingPathComponent("metadata.json")
        let zipURL = folderURL.appendingPathComponent("input_data.zip")
        let fm = FileManager.default
        
        // First, immediately notify Flutter about the scan completion so UI updates
        DispatchQueue.main.async { [weak self] in
            self?.channel?.invokeMethod("scanComplete", arguments: args) { invokeResult in
                if let error = invokeResult as? FlutterError {
                    os_log("❌ [SCAN COMPLETE] Failed to notify Flutter: %@", log: OSLog.default, type: .error, error.message ?? "Unknown error")
                } else {
                    os_log("✅ [SCAN COMPLETE] Flutter notified successfully", log: OSLog.default, type: .info)
                }
            }
        }
        
        // Check if scan data is complete for upload
        if fm.fileExists(atPath: metaURL.path) && fm.fileExists(atPath: zipURL.path) {
            // Handle based on online/offline status AND auto-sync setting
            if isOnline && autoSyncEnabled {
                os_log("🚀 [SCAN COMPLETE] Online + Auto-sync enabled - uploading to server and saving locally: %@", log: OSLog.default, type: .info, folderPath)
                uploadScan(folderURL: folderURL) { [weak self] success in
                    if success {
                        os_log("✅ [SCAN COMPLETE] Successfully uploaded: %@", log: OSLog.default, type: .info, folderPath)
                        
                        // Set local status to pending (data saved both in API and locally)
                        _ = ScanLocalStorage.shared.updateScanStatus("pending", for: folderURL)
                        
                        // Notify Flutter about successful upload
                        DispatchQueue.main.async {
                            self?.channel?.invokeMethod("scanUploadComplete", arguments: [
                                "folderPath": folderPath,
                                "success": true
                            ])
                        }
                    } else {
                        os_log("❌ [SCAN COMPLETE] Upload failed while online, marking as pending for retry: %@", log: OSLog.default, type: .error, folderPath)
                        
                        // Mark as pending for later upload retry (since we had connectivity during scan)
                        _ = ScanLocalStorage.shared.updateScanStatus("pending", for: folderURL)
                        
                        // Notify Flutter about failed upload
                        DispatchQueue.main.async {
                            self?.channel?.invokeMethod("scanUploadComplete", arguments: [
                                "folderPath": folderPath,
                                "success": false
                            ])
                        }
                    }
                }
            } else if isOnline && !autoSyncEnabled {
                os_log("⏸️ [SCAN COMPLETE] Online but auto-sync disabled - saving locally with initialized status for manual sync: %@", log: OSLog.default, type: .info, folderPath)
                // When auto-sync is disabled, save with initialized status for manual sync
                _ = ScanLocalStorage.shared.updateScanStatus("initialized", for: folderURL)
            } else {
                os_log("📱 [SCAN COMPLETE] Offline - saving locally with initialized status: %@", log: OSLog.default, type: .info, folderPath)
                // When offline, save locally with initialized status for later sync
                _ = ScanLocalStorage.shared.updateScanStatus("initialized", for: folderURL)
            }
        } else {
            os_log("⚠️ [SCAN COMPLETE] Scan data incomplete - missing metadata or zip: %@", log: OSLog.default, type: .error, folderPath)
            _ = ScanLocalStorage.shared.updateScanStatus("failed", for: folderURL)
        }
        
        // Test method channel connectivity after scan completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.testMethodChannelConnectivity()
        }
        
        result("Scan complete notification processed")
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
            self.scanViewController = scanVC // Retain the controller to prevent deallocation
            scanVC.modalPresentationStyle = .fullScreen
            controller.present(scanVC, animated: true) {
                result("Scan started")
            }
        }
    }

    private func handleCloseARModule(result: @escaping FlutterResult) {
        // Release the strong reference to scanViewController to prevent memory leaks
        os_log("🚪 [CLOSE AR MODULE] Releasing scanViewController reference", log: OSLog.default, type: .info)
        self.scanViewController = nil
        result("AR Module closed and resources released")
    }

    private func uploadScan(folderURL: URL, completion: @escaping (Bool) -> Void) {
        os_log("🚀 [UPLOAD SCAN] Method called with folder: %@", log: OSLog.default, type: .info, folderURL.path)
        
        guard let metadataData = try? Data(contentsOf: folderURL.appendingPathComponent("metadata.json")),
              let zipData = try? Data(contentsOf: folderURL.appendingPathComponent("input_data.zip")) else {
            os_log("❌ [UPLOAD SCAN] Failed to read metadata or ZIP data", log: OSLog.default, type: .error)
            completion(false)
            return
        }
        
        os_log("✅ [UPLOAD SCAN] Successfully read metadata (%d bytes) and ZIP (%d bytes)", log: OSLog.default, type: .info, metadataData.count, zipData.count)

            // Build JSON payload for /scans/ create
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var title = folderURL.lastPathComponent
            var durationSeconds: Double = 0
            var modelBytes: Int64 = 0
            var locationName: String = ""
            var coordinates: [[Double]] = []
            
            // Calculate actual file sizes
            let zipURL = folderURL.appendingPathComponent("input_data.zip")
            let usdzURL = folderURL.appendingPathComponent("model.usdz")
            
            var zipSizeBytes: Int64 = 0
            var usdzSizeBytes: Int64 = 0
            
            if FileManager.default.fileExists(atPath: zipURL.path),
               let zipAttributes = try? FileManager.default.attributesOfItem(atPath: zipURL.path),
               let zipSize = zipAttributes[.size] as? Int64 {
                zipSizeBytes = zipSize
            }
            
            if FileManager.default.fileExists(atPath: usdzURL.path),
               let usdzAttributes = try? FileManager.default.attributesOfItem(atPath: usdzURL.path),
               let usdzSize = usdzAttributes[.size] as? Int64 {
                usdzSizeBytes = usdzSize
            }
            
            let totalSizeBytes = zipSizeBytes + usdzSizeBytes
            
            if let meta = try? decoder.decode(ScanMetadata.self, from: metadataData) {
                title = meta.name
                durationSeconds = meta.durationSeconds ?? 0
                modelBytes = totalSizeBytes > 0 ? totalSizeBytes : (meta.modelSizeBytes ?? 0)
                locationName = meta.locationName ?? ""
                coordinates = meta.coordinates ?? []
                
                os_log("📊 [UPLOAD SCAN] Model data - Title: %@, Duration: %.1f, Size: %d bytes (%.2f MB), Location: %@, Coordinates: %d", log: OSLog.default, type: .info, title, durationSeconds, modelBytes, Double(modelBytes) / (1024.0 * 1024.0), locationName, coordinates.count)
            }
            // Calculate scan area and height from sceneBounds if available in metadata
            var areaCovered = 0.0
            var height = 0.0
            
            if let meta = try? decoder.decode(ScanMetadata.self, from: metadataData),
               let boundsSizeStr = meta.boundsSize {
                // Parse bounds size string format: "[width, depth, height]"
                let cleanedStr = boundsSizeStr.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                let components = cleanedStr.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                
                if components.count >= 3 {
                    let width = components[0]
                    let depth = components[1]
                    height = components[2]
                    
                    // Calculate area in square meters (width × depth)
                    areaCovered = width * depth
                }
            }
            
            let payload: [String: Any] = [
                "title": title,
                "description": "Uploaded from iOS app",
                "duration": Int(durationSeconds),
                "area_covered": areaCovered,
                "height": height,
                "data_size_mb": Double(modelBytes) / (1024.0 * 1024.0),
                "location": locationName.isEmpty ? "Unknown" : locationName
            ]

            // Step 1: Create scan
            guard let createURL = URL(string: "\(apiBaseURL)/scans/") else { completion(false); return }
            var createReq = URLRequest(url: createURL)
            createReq.httpMethod = "POST"
            createReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            createReq.setValue("application/json", forHTTPHeaderField: "Accept")
            if let token = readAuthToken(), !token.isEmpty { createReq.setValue("Token \(token)", forHTTPHeaderField: "Authorization") }
            createReq.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            
            // Log the create scan request
            os_log("🚀 [CREATE SCAN] POST %@", log: OSLog.default, type: .info, createURL.absoluteString)
            os_log("📋 [CREATE SCAN] Headers: %@", log: OSLog.default, type: .info, createReq.allHTTPHeaderFields?.description ?? "None")
            os_log("📦 [CREATE SCAN] Body: %@", log: OSLog.default, type: .info, String(data: createReq.httpBody ?? Data(), encoding: .utf8) ?? "None")

            URLSession.shared.dataTask(with: createReq) { data, response, error in
                if let error = error {
                    os_log("❌ [CREATE SCAN] Failed: %@", log: OSLog.default, type: .error, error.localizedDescription)
                    completion(false)
                    return
                }
                guard let data = data, let http = response as? HTTPURLResponse, (200...201).contains(http.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    os_log("❌ [CREATE SCAN] Unexpected status: %d", log: OSLog.default, type: .error, statusCode)
                    if let responseData = data, let responseString = String(data: responseData, encoding: .utf8) {
                        os_log("📥 [CREATE SCAN] Response: %@", log: OSLog.default, type: .error, responseString)
                    }
                    completion(false)
                    return
                }
                var scanId: Int?
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { scanId = obj["id"] as? Int }
                guard let sid = scanId else {
                    os_log("❌ [CREATE SCAN] Missing id in response", log: OSLog.default, type: .error)
                    completion(false)
                    return
                }
                
                os_log("✅ [CREATE SCAN] Success! Scan ID: %d", log: OSLog.default, type: .info, sid)
                
                // Step 2: Upload point cloud zip to /scans/{scan_id}/point-cloud/
                guard let pcURL = URL(string: "\(self.apiBaseURL)/scans/\(sid)/point-cloud/") else { completion(true); return }
                var pcReq = URLRequest(url: pcURL)
                pcReq.httpMethod = "POST"
                let boundary = "Boundary-\(UUID().uuidString)"
                pcReq.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                if let token = self.readAuthToken(), !token.isEmpty { pcReq.setValue("Token \(token)", forHTTPHeaderField: "Authorization") }
                var body = Data()
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"gray_model\"; filename=\"input_data.zip\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: application/zip\r\n\r\n".data(using: .utf8)!)
                body.append(zipData)
                body.append("\r\n".data(using: .utf8)!)
                // Add required point_count field
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"point_count\"\r\n\r\n".data(using: .utf8)!)
                body.append("1000000".data(using: .utf8)!) // Default point count, adjust as needed
                body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
                pcReq.httpBody = body
                
                // Log the point cloud upload request
                os_log("🚀 [POINT CLOUD] POST %@", log: OSLog.default, type: .info, pcURL.absoluteString)
                os_log("📋 [POINT CLOUD] Headers: %@", log: OSLog.default, type: .info, pcReq.allHTTPHeaderFields?.description ?? "None")
                os_log("📦 [POINT CLOUD] Body size: %d bytes, Boundary: %@", log: OSLog.default, type: .info, body.count, boundary)
                
                URLSession.shared.dataTask(with: pcReq) { _, response, error in
                    if let error = error {
                        os_log("❌ [POINT CLOUD] Failed: %@", log: OSLog.default, type: .error, error.localizedDescription)
                    } else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        os_log("✅ [POINT CLOUD] Status: %d", log: OSLog.default, type: .info, statusCode)
                    }
                    
                    // Step 3: Upload GPS points (if any)
                    self.uploadGPSPoints(scanId: sid, metadataData: metadataData) { _ in
                        // Step 4: Upload images (if any)
                        self.uploadScanImages(scanId: sid, folderURL: folderURL) { _ in
                            // Step 5: Post upload status - uploaded scans should be pending for processing
                            self.postUploadStatus(scanId: sid, status: "pending", errorMessage: nil) { _ in
                                completion(true)
                            }
                        }
                    }
                }.resume()
            }.resume()
        }

        private func uploadPointCloud(scanId: Int, zipData: Data, completion: @escaping (Bool) -> Void) {
            // Try point-cloud endpoint first using field name 'gray_model'. If it fails, try 'file'. If still fails, send to process endpoint.
            func multipartRequest(fieldName: String) -> URLRequest? {
                guard let pcURL = URL(string: "\(self.apiBaseURL)/scans/\(scanId)/point-cloud/") else { return nil }
                var req = URLRequest(url: pcURL)
                req.httpMethod = "POST"
                let boundary = "Boundary-\(UUID().uuidString)"
                req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                if let token = self.readAuthToken(), !token.isEmpty { req.setValue("Token \(token)", forHTTPHeaderField: "Authorization") }
                var body = Data()
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"input_data.zip\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: application/zip\r\n\r\n".data(using: .utf8)!)
                body.append(zipData)
                body.append("\r\n".data(using: .utf8)!)
                // Add required point_count field
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"point_count\"\r\n\r\n".data(using: .utf8)!)
                body.append("1000000".data(using: .utf8)!) // Default point count, adjust as needed
                body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
                req.httpBody = body
                return req
            }
            func processEndpointFallback() {
                guard let processURL = URL(string: "\(self.apiBaseURL)/scans/process/") else { completion(false); return }
                var req = URLRequest(url: processURL)
                req.httpMethod = "POST"
                req.setValue("application/zip", forHTTPHeaderField: "Content-Type")
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                if let token = self.readAuthToken(), !token.isEmpty { req.setValue("Token \(token)", forHTTPHeaderField: "Authorization") }
                req.httpBody = zipData
                URLSession.shared.dataTask(with: req) { data, response, error in
                    if let error = error {
                        os_log("Process endpoint error: %@", log: OSLog.default, type: .error, error.localizedDescription)
                        completion(false)
                        return
                    }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    if status == 200 || status == 201 || status == 202 {
                        os_log("Process endpoint accepted zip (status %d)", log: OSLog.default, type: .info, status)
                        completion(true)
                    } else {
                        os_log("Process endpoint unexpected status %d", log: OSLog.default, type: .error, status)
                        completion(false)
                    }
                }.resume()
            }

            // Try with 'gray_model'
            if var req = multipartRequest(fieldName: "gray_model") {
                URLSession.shared.dataTask(with: req) { _, response, _ in
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    if status == 200 || status == 201 {
                        completion(true)
                    } else {
                        // Try with 'file'
                        if let req2 = multipartRequest(fieldName: "file") {
                            URLSession.shared.dataTask(with: req2) { _, response2, _ in
                                let status2 = (response2 as? HTTPURLResponse)?.statusCode ?? -1
                                if status2 == 200 || status2 == 201 {
                                    completion(true)
                                } else {
                                    // Fallback to process endpoint
                                    processEndpointFallback()
                                }
                            }.resume()
                        } else {
                            processEndpointFallback()
                        }
                    }
                }.resume()
            } else {
                processEndpointFallback()
            }
        }

        private func uploadGPSPoints(scanId: Int, metadataData: Data, completion: @escaping (Bool) -> Void) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            // Debug: Log the metadata content
            if let metadataString = String(data: metadataData, encoding: .utf8) {
                os_log("📋 [GPS POINTS] Metadata content for scan %d: %@", log: OSLog.default, type: .info, scanId, metadataString)
            }
            
            let meta: ScanMetadata?
            do {
                meta = try decoder.decode(ScanMetadata.self, from: metadataData)
            } catch {
                os_log("❌ [GPS POINTS] Failed to decode metadata for scan %d: %@", log: OSLog.default, type: .error, scanId, error.localizedDescription)
                completion(true)
                return
            }
            
            guard let meta = meta, let coords = meta.coordinates, !coords.isEmpty else {
                os_log("ℹ️ [GPS POINTS] No GPS coordinates found in metadata for scan %d. Meta: %@", log: OSLog.default, type: .info, scanId, String(describing: meta))
                completion(true)
                return
            }
            
            os_log("🚀 [GPS POINTS] Found %d GPS coordinates to upload for scan %d", log: OSLog.default, type: .info, coords.count, scanId)
            let group = DispatchGroup()
            var allOk = true
                for (index, coord) in coords.enumerated() {
                if coord.count < 2 { continue }
                let lat = coord[0]
                let lon = coord[1]

                os_log("📍 [GPS POINTS] Uploading GPS point %d: lat=%.6f, lon=%.6f", log: OSLog.default, type: .info, index + 1, lat, lon)

                guard let url = URL(string: "\(apiBaseURL)/scans/\(scanId)/gps-points/") else { continue }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                if let token = readAuthToken(), !token.isEmpty { req.setValue("Token \(token)", forHTTPHeaderField: "Authorization") }
                
                // Send only latitude and longitude as per GPSPathSerializer
                // Ensure proper latitude/longitude assignment
                let body: [String: Any] = [
                    "latitude": lat,
                    "longitude": lon
                ]
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                
                // Log the GPS point upload request
                os_log("🚀 [GPS POINTS] POST %@ (Point %d)", log: OSLog.default, type: .info, url.absoluteString, index + 1)
                os_log("📋 [GPS POINTS] Headers: %@", log: OSLog.default, type: .info, req.allHTTPHeaderFields?.description ?? "None")
                os_log("📦 [GPS POINTS] Body: %@", log: OSLog.default, type: .info, String(data: req.httpBody ?? Data(), encoding: .utf8) ?? "None")
                
                group.enter()
                URLSession.shared.dataTask(with: req) { data, response, error in
                    if let error = error { 
                        os_log("❌ [GPS POINTS] Point %d upload failed: %@", log: OSLog.default, type: .error, index + 1, error.localizedDescription)
                        allOk = false 
                    }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    if !(status == 200 || status == 201 || status == 204) { 
                        os_log("❌ [GPS POINTS] Point %d upload failed with status %d", log: OSLog.default, type: .error, index + 1, status)
                        // Log response body for debugging
                        if let data = data, let responseString = String(data: data, encoding: .utf8) {
                            os_log("📥 [GPS POINTS] Response body: %@", log: OSLog.default, type: .error, responseString)
                        }
                        allOk = false 
                    } else {
                        os_log("✅ [GPS POINTS] Point %d uploaded successfully (Status: %d)", log: OSLog.default, type: .info, index + 1, status)
                        // Log successful response for debugging
                        if let data = data, let responseString = String(data: data, encoding: .utf8) {
                            os_log("📥 [GPS POINTS] Success response: %@", log: OSLog.default, type: .info, responseString)
                        }
                    }
                    group.leave()
                }.resume()
            }
            group.notify(queue: .main) { completion(allOk) }
        }

        private func uploadScanImages(scanId: Int, folderURL: URL, completion: @escaping (Bool) -> Void) {
            guard let imagePaths = ScanLocalStorage.shared.getScanImages(folderPath: folderURL.path), !imagePaths.isEmpty else {
                os_log("ℹ️ [IMAGES] No images found for scan %d", log: OSLog.default, type: .info, scanId)
                completion(true)
                return
            }
            
            os_log("🚀 [IMAGES] Found %d images to upload for scan %d", log: OSLog.default, type: .info, imagePaths.count, scanId)
            let group = DispatchGroup()
            var allOk = true
            for (index, imagePath) in imagePaths.enumerated() {
                let fileURL = URL(fileURLWithPath: imagePath)
                guard let imageData = try? Data(contentsOf: fileURL) else { 
                    os_log("⚠️ [IMAGES] Failed to read image data for %@", log: OSLog.default, type: .error, imagePath)
                    continue 
                }
                
                guard let url = URL(string: "\(apiBaseURL)/scans/\(scanId)/images/") else { continue }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                let boundary = "Boundary-\(UUID().uuidString)"
                req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                if let token = readAuthToken(), !token.isEmpty { req.setValue("Token \(token)", forHTTPHeaderField: "Authorization") }
                var body = Data()
                // image field per server
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
                body.append(imageData)
                body.append("\r\n".data(using: .utf8)!)
                // optional caption
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"caption\"\r\n\r\n".data(using: .utf8)!)
                body.append("".data(using: .utf8)!)
                body.append("\r\n".data(using: .utf8)!)
                // optional timestamp
                let iso = ISO8601DateFormatter().string(from: Date())
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"timestamp\"\r\n\r\n".data(using: .utf8)!)
                body.append(iso.data(using: .utf8)!)
                body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
                req.httpBody = body
                
                // Log the image upload request
                os_log("🚀 [IMAGES] POST %@ (Image %d: %@)", log: OSLog.default, type: .info, url.absoluteString, index + 1, fileURL.lastPathComponent)
                os_log("📋 [IMAGES] Headers: %@", log: OSLog.default, type: .info, req.allHTTPHeaderFields?.description ?? "None")
                os_log("📦 [IMAGES] Body size: %d bytes, Boundary: %@", log: OSLog.default, type: .info, body.count, boundary)
                
                group.enter()
                URLSession.shared.dataTask(with: req) { _, response, error in
                    if let error = error { 
                        os_log("❌ [IMAGES] Image %d upload failed: %@", log: OSLog.default, type: .error, index + 1, error.localizedDescription)
                        allOk = false 
                    }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    if !(status == 200 || status == 201) { 
                        os_log("❌ [IMAGES] Image %d upload failed with status %d", log: OSLog.default, type: .error, index + 1, status)
                        allOk = false 
                    } else {
                        os_log("✅ [IMAGES] Image %d uploaded successfully (Status: %d)", log: OSLog.default, type: .info, index + 1, status)
                    }
                    group.leave()
                }.resume()
            }
            group.notify(queue: .main) { completion(allOk) }
        }

        private func postUploadStatus(scanId: Int, status: String, errorMessage: String?, completion: @escaping (Bool) -> Void) {
            guard let url = URL(string: "\(apiBaseURL)/scans/\(scanId)/upload-status/") else { completion(false); return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            if let token = readAuthToken(), !token.isEmpty { req.setValue("Token \(token)", forHTTPHeaderField: "Authorization") }
            let iso = ISO8601DateFormatter().string(from: Date())
            
            // Map status to Django model choices: 'pending', 'uploading', 'failed', 'completed'
            let djangoStatus: String
            switch status {
            case "processed":
                djangoStatus = "completed"
            case "uploaded":
                djangoStatus = "pending"  // New scans should be pending, not completed
            case "failed":
                djangoStatus = "failed"
            case "pending":
                djangoStatus = "pending"
            default:
                djangoStatus = "uploading"
            }
            
            let body: [String: Any] = [
                "status": djangoStatus,
                "last_attempt": iso,
                "retry_count": 0,
                "error_message": errorMessage ?? ""
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            URLSession.shared.dataTask(with: req) { _, response, error in
                if let error = error { os_log("Upload-status post failed: %@", log: OSLog.default, type: .error, error.localizedDescription); completion(false); return }
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                completion(statusCode == 200 || statusCode == 201 || statusCode == 204)
            }.resume()
        }

    private func getSavedScans(result: @escaping FlutterResult) {
        os_log("📱 [GET SAVED SCANS] Method called, online: %@", log: OSLog.default, type: .info, isOnline ? "YES" : "NO")
        
        // Always return a valid response structure, even if empty
        os_log("📱 [GET SAVED SCANS] Getting local scans...", log: OSLog.default, type: .info)
        
        // If online, fetch from API and merge with local scans
        if isOnline {
            fetchAPIScans { [weak self] apiScans in
                guard self != nil else { return }
                
                DispatchQueue.main.async {
                    let localScans = ScanLocalStorage.shared.getAllScans()
                    var scanList: [[String: Any]] = []
                    
                    // Add API scans first (uploaded scans from server)
                    if let apiScans = apiScans {
                        os_log("📡 [GET SAVED SCANS] Fetched %d scans from API", log: OSLog.default, type: .info, apiScans.count)
                        for apiScan in apiScans {
                            let scanDict: [String: Any] = [
                                "id": apiScan.scanID,
                                "name": apiScan.name,
                                "timestamp": apiScan.timestamp.timeIntervalSince1970,
                                "status": apiScan.status, // Use actual status from API
                                "imageCount": apiScan.imageCount,
                                "modelSizeBytes": apiScan.modelSizeBytes ?? 0,
                                "durationSeconds": apiScan.durationSeconds ?? 0.0,
                                "folderPath": "", // API scans don't have local folder paths
                                "hasUSDZ": false, // API scans don't have local USDZ files
                                "locationName": apiScan.locationName ?? "",
                                "isFromAPI": true, // Flag to distinguish API scans
                                "scanID": apiScan.scanID // Add scanID for compatibility
                            ]
                            scanList.append(scanDict)
                        }
                    } else {
                        os_log("⚠️ [GET SAVED SCANS] Failed to fetch API scans, falling back to local only", log: OSLog.default, type: .error)
                    }
                                        
                    // Sort by timestamp (newest first)
                    scanList.sort { (scan1, scan2) in
                        let timestamp1 = scan1["timestamp"] as? TimeInterval ?? 0
                        let timestamp2 = scan2["timestamp"] as? TimeInterval ?? 0
                        return timestamp1 > timestamp2
                    }
                    
                    os_log("📱 [GET SAVED SCANS] Returning %d total scans (API + Local)", log: OSLog.default, type: .info, scanList.count)
                    result(["scans": scanList])
                }
            }
        } else {
            // Offline: return only local scans
            DispatchQueue.main.async {
                let localScans = ScanLocalStorage.shared.getAllScans()
                var scanList: [[String: Any]] = []
                
                for scan in localScans {
                    if let metadata = scan.metadata {
                        var scanDict: [String: Any] = [
                            "id": metadata.scanID,
                            "name": metadata.name,
                            "timestamp": metadata.timestamp.timeIntervalSince1970,
                            "status": metadata.status,
                            "imageCount": metadata.imageCount,
                            "modelSizeBytes": metadata.modelSizeBytes ?? 0,
                            "durationSeconds": metadata.durationSeconds ?? 0.0,
                            "folderPath": scan.url.path,
                            "hasUSDZ": ScanLocalStorage.shared.hasUSDZModel(in: scan.url),
                            "isFromAPI": false
                        ]
                        
                        if let locationName = metadata.locationName {
                            scanDict["locationName"] = locationName
                        }
                        
                        if let coordinates = metadata.coordinates, !coordinates.isEmpty {
                            scanDict["coordinates"] = coordinates
                        }
                        
                        if let snapshotPath = metadata.snapshotPath {
                            scanDict["snapshotPath"] = snapshotPath
                        }
                        
                        scanList.append(scanDict)
                    }
                }
                
                // Sort by timestamp (newest first)
                scanList.sort { (scan1, scan2) in
                    let timestamp1 = scan1["timestamp"] as? TimeInterval ?? 0
                    let timestamp2 = scan2["timestamp"] as? TimeInterval ?? 0
                    return timestamp1 > timestamp2
                }
                
                os_log("📱 [GET SAVED SCANS] Returning %d local scans (OFFLINE)", log: OSLog.default, type: .info, scanList.count)
                result(["scans": scanList])
            }
        }
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

    private func invalidateScanCache() {
        scanCache = nil
        os_log("Invalidated scan cache", log: OSLog.default, type: .info)
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
            // Configure for iPad to avoid UIPopoverPresentationController crash
            if UIDevice.current.userInterfaceIdiom == .pad {
                activityVC.popoverPresentationController?.sourceView = controller.view
                activityVC.popoverPresentationController?.sourceRect = CGRect(
                    x: controller.view.bounds.midX,
                    y: controller.view.bounds.midY,
                    width: 0,
                    height: 0
                )
                activityVC.popoverPresentationController?.permittedArrowDirections = []
            }

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

        channel?.invokeMethod("updateProcessingStatus", arguments: ["status": "processing"]) { error in
            if let error = error {
                os_log("Failed to notify Flutter of processing start: %@", log: OSLog.default, type: .error, (error as AnyObject).localizedDescription)
            }
        }

        let timeout: TimeInterval = 300
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let timeoutDate = Date().addingTimeInterval(timeout)
            modelVC.processZipFile(at: zipURL) { [weak self] processResult in
                guard let self = self else { return }
                defer { self.modelVC = nil }

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
                    // Send POST request to backend for successful processing
                    self.uploadProcessedScan(folderURL: scanFolderURL, usdzURL: usdzURL, modelSizeBytes: modelSizeBytes) { uploadSuccess in
                        if uploadSuccess {
                            os_log("✅ Successfully uploaded processed scan to backend", log: OSLog.default, type: .info)
                        } else {
                            os_log("⚠️ Failed to upload processed scan to backend", log: OSLog.default, type: .error)
                        }
                    }
                    self.channel?.invokeMethod("processingComplete", arguments: [
                        "folderPath": scanFolderURL.path,
                        "usdzPath": usdzURL.path,
                        "modelSizeBytes": modelSizeBytes
                    ]) { invokeResult in
                        if let error = invokeResult as? FlutterError {
                            os_log("Failed to invoke processingComplete: %@", log: OSLog.default, type: .error, error.message ?? "Unknown error")
                        }
                    }
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
                    // Send POST request to backend for failed processing
                    self.uploadFailedScan(folderURL: scanFolderURL, error: error) { uploadSuccess in
                        if uploadSuccess {
                            os_log("✅ Successfully uploaded failed scan status to backend", log: OSLog.default, type: .info)
                        } else {
                            os_log("⚠️ Failed to upload failed scan status to backend", log: OSLog.default, type: .error)
                        }
                    }
                    self.channel?.invokeMethod("processingComplete", arguments: [
                        "folderPath": scanFolderURL.path,
                        "status": "failed"
                    ]) { invokeResult in
                        if let error = invokeResult as? FlutterError {
                            os_log("Failed to invoke processingComplete: %@", log: OSLog.default, type: .error, error.message ?? "Unknown error")
                        }
                    }
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


    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return currentUSDZURL != nil ? 1 : 0
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return currentUSDZURL! as QLPreviewItem
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        openFolderResult?("Folder opened successfully")
        openFolderResult = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        openFolderResult?("Folder open cancelled")
        openFolderResult = nil
    }
    
    // MARK: - Upload Helper Methods
    
    private func uploadProcessedScan(folderURL: URL, usdzURL: URL, modelSizeBytes: Int64, completion: @escaping (Bool) -> Void) {
        // First, try to get or create the scan record on the backend
        self.ensureScanExistsOnBackend(folderURL: folderURL) { [weak self] (scanId: Int?) in
            guard let self = self, let scanId = scanId else {
                os_log("Failed to ensure scan exists on backend for processed scan", log: OSLog.default, type: .error)
                completion(false)
                return
            }
            
            // Upload the processed USDZ model to point-cloud endpoint
            self.uploadProcessedModel(scanId: scanId, usdzURL: usdzURL) { modelUploadSuccess in
                if modelUploadSuccess {
                    // Update upload status to indicate successful processing
                    self.postUploadStatus(scanId: scanId, status: "processed", errorMessage: nil) { statusSuccess in
                        completion(statusSuccess)
                    }
                } else {
                    completion(false)
                }
            }
        }
    }
    
    private func uploadFailedScan(folderURL: URL, error: FlutterError, completion: @escaping (Bool) -> Void) {
        // First, try to get or create the scan record on the backend
        self.ensureScanExistsOnBackend(folderURL: folderURL) { [weak self] (scanId: Int?) in
            guard let self = self, let scanId = scanId else {
                os_log("Failed to ensure scan exists on backend for failed scan", log: OSLog.default, type: .error)
                completion(false)
                return
            }
            
            // Post upload status indicating processing failure
            let errorMessage = error.message ?? "Unknown processing error"
            self.postUploadStatus(scanId: scanId, status: "failed", errorMessage: errorMessage) { statusSuccess in
                completion(statusSuccess)
            }
        }
    }
    
    private func ensureScanExistsOnBackend(folderURL: URL, completion: @escaping (Int?) -> Void) {
        // Check if scan already exists by trying to upload basic scan data
        let metadataURL = folderURL.appendingPathComponent("metadata.json")
        let zipURL = folderURL.appendingPathComponent("input_data.zip")
        
        guard let metadataData = try? Data(contentsOf: metadataURL),
              let _ = try? Data(contentsOf: zipURL) else {
            completion(nil)
            return
        }
        
        // Try to create scan record on backend
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var title = folderURL.lastPathComponent
        var durationSeconds: Double = 0
        var modelBytes: Int64 = 0
        var locationName: String = ""
        
        if let meta = try? decoder.decode(ScanMetadata.self, from: metadataData) {
            title = meta.name
            durationSeconds = meta.durationSeconds ?? 0
            modelBytes = meta.modelSizeBytes ?? 0
            locationName = meta.locationName ?? ""
        }
        
        let payload: [String: Any] = [
            "title": title,
            "description": "Processed scan from iOS app",
            "duration": Int(durationSeconds),
            "area_covered": 0,
            "height": 0,
            "data_size_mb": Double(modelBytes) / (1024.0 * 1024.0),
            "location": locationName.isEmpty ? "Unknown" : locationName
        ]
        
        guard let createURL = URL(string: "\(apiBaseURL)/scans/") else { completion(nil); return }
        var createReq = URLRequest(url: createURL)
        createReq.httpMethod = "POST"
        createReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        createReq.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = readAuthToken(), !token.isEmpty { createReq.setValue("Token \(token)", forHTTPHeaderField: "Authorization") }
        createReq.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: createReq) { data, response, error in
            if let error = error {
                os_log("Failed to create scan record for processed scan: %@", log: OSLog.default, type: .error, error.localizedDescription)
                completion(nil)
                return
            }
            
            guard let data = data, let http = response as? HTTPURLResponse, (200...201).contains(http.statusCode) else {
                os_log("Failed to create scan record for processed scan - unexpected status", log: OSLog.default, type: .error)
                completion(nil)
                return
            }
            
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let scanId = obj["id"] as? Int {
                completion(scanId)
            } else {
                completion(nil)
            }
        }.resume()
    }
    
    private func uploadProcessedModel(scanId: Int, usdzURL: URL, completion: @escaping (Bool) -> Void) {
        guard let usdzData = try? Data(contentsOf: usdzURL) else {
            os_log("Failed to read USDZ data for upload", log: OSLog.default, type: .error)
            completion(false)
            return
        }
        
        // Try to upload to point-cloud endpoint with processed_model field
        guard let pcURL = URL(string: "\(apiBaseURL)/scans/\(scanId)/point-cloud/") else { completion(false); return }
        var pcReq = URLRequest(url: pcURL)
        pcReq.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        pcReq.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = readAuthToken(), !token.isEmpty { pcReq.setValue("Token \(token)", forHTTPHeaderField: "Authorization") }
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"processed_model\"; filename=\"model.usdz\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: model/vnd.usdz+zip\r\n\r\n".data(using: .utf8)!)
        body.append(usdzData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        pcReq.httpBody = body
        
        URLSession.shared.dataTask(with: pcReq) { _, response, error in
            if let error = error {
                os_log("Failed to upload processed model: %@", log: OSLog.default, type: .error, error.localizedDescription)
                completion(false)
                return
            }
            
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            if statusCode == 200 || statusCode == 201 {
                os_log("Successfully uploaded processed model to backend", log: OSLog.default, type: .info)
                completion(true)
            } else {
                os_log("Failed to upload processed model - status %d", log: OSLog.default, type: .error, statusCode)
                completion(false)
            }
        }.resume()
    }

    private func handleUploadScanToBackend(call: FlutterMethodCall, result: @escaping FlutterResult) {
        os_log("🔍 [UPLOAD HANDLER] Method called with arguments: %@", log: OSLog.default, type: .info, String(describing: call.arguments))
        
        guard let args = call.arguments as? [String: Any],
              let folderPath = args["folderPath"] as? String else {
            os_log("❌ [UPLOAD HANDLER] Invalid arguments: %@", log: OSLog.default, type: .error, String(describing: call.arguments))
            result(FlutterError(
                code: "INVALID_ARGUMENT",
                message: "Invalid or missing folder path for uploadScanToBackend.",
                details: nil
            ))
            return
        }

        let folderURL = URL(fileURLWithPath: folderPath)
        let metadataURL = folderURL.appendingPathComponent("metadata.json")
        let zipURL = folderURL.appendingPathComponent("input_data.zip")

        os_log("🔍 [UPLOAD HANDLER] Checking files at: %@", log: OSLog.default, type: .info, folderPath)
        os_log("🔍 [UPLOAD HANDLER] Metadata exists: %@", log: OSLog.default, type: .info, FileManager.default.fileExists(atPath: metadataURL.path) ? "YES" : "NO")
        os_log("🔍 [UPLOAD HANDLER] ZIP exists: %@", log: OSLog.default, type: .info, FileManager.default.fileExists(atPath: zipURL.path) ? "YES" : "NO")

        guard FileManager.default.fileExists(atPath: metadataURL.path) && FileManager.default.fileExists(atPath: zipURL.path) else {
            os_log("❌ [UPLOAD HANDLER] Required files not found", log: OSLog.default, type: .error)
            result(FlutterError(
                code: "FILE_NOT_FOUND",
                message: "Metadata or ZIP file not found for folder: \(folderPath)",
                details: nil
            ))
            return
        }

        // Trigger the full upload flow immediately
        os_log("🚀 [UPLOAD HANDLER] Starting immediate backend upload for scan: %@", log: OSLog.default, type: .info, folderPath)
        
        self.uploadScan(folderURL: folderURL) { success in
            os_log("📱 [UPLOAD HANDLER] uploadScan completion called with success: %@", log: OSLog.default, type: .info, success ? "YES" : "NO")
            if success {
                os_log("✅ [UPLOAD HANDLER] Successfully uploaded scan to backend immediately after completion", log: OSLog.default, type: .info)
                result("Scan Saved successfully")
            } else {
                os_log("⚠️ [UPLOAD HANDLER] Failed to upload scan to backend immediately after completion", log: OSLog.default, type: .error)
                result(FlutterError(
                    code: "BACKEND_ERROR",
                    message: "Failed to upload scan to backend immediately after completion.",
                    details: nil
                ))
            }
        }
        
        os_log("🔍 [UPLOAD HANDLER] uploadScan method called, waiting for completion...", log: OSLog.default, type: .info)
    }
    
    
    // MARK: - Method Channel Testing
    
    /**
     * Tests method channel connectivity by sending a test message to Flutter.
     * This helps ensure the channel is still working after memory warnings or other events.
     */
    private func testMethodChannelConnectivity() {
        guard let channel = self.channel else {
            os_log("⚠️ [METHOD CHANNEL TEST] Channel is nil", log: OSLog.default, type: .error)
            return
        }
        
        os_log("🔍 [METHOD CHANNEL TEST] Testing method channel connectivity...", log: OSLog.default, type: .info)
        
        channel.invokeMethod("testConnectivity", arguments: [
            "timestamp": Date().timeIntervalSince1970,
            "source": "ios_native"
        ]) { result in
            if let error = result as? FlutterError {
                os_log("❌ [METHOD CHANNEL TEST] Test failed: %@ - %@", log: OSLog.default, type: .error, error.code, error.message ?? "Unknown error")
            } else {
                os_log("✅ [METHOD CHANNEL TEST] Test successful, channel is responsive", log: OSLog.default, type: .info)
            }
        }
    }
    
    @objc private func handleUploadNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let folderPath = userInfo["folderPath"] as? String else {
            os_log("❌ [UPLOAD NOTIFICATION] Invalid notification data", log: OSLog.default, type: .error)
            return
        }
        
        os_log("🔔 [UPLOAD NOTIFICATION] Received upload request for: %@, online: %@", log: OSLog.default, type: .info, folderPath, isOnline ? "YES" : "NO")
        
        let folderURL = URL(fileURLWithPath: folderPath)
        let metadataURL = folderURL.appendingPathComponent("metadata.json")
        let zipURL = folderURL.appendingPathComponent("input_data.zip")

        guard FileManager.default.fileExists(atPath: metadataURL.path) && FileManager.default.fileExists(atPath: zipURL.path) else {
            os_log("❌ [UPLOAD NOTIFICATION] Required files not found", log: OSLog.default, type: .error)
            return
        }

        // Only upload if we're online AND auto-sync is enabled
        if isOnline && autoSyncEnabled {
            // Trigger the full upload flow immediately
            os_log("🚀 [UPLOAD NOTIFICATION] Online + Auto-sync enabled - starting immediate backend upload for scan: %@", log: OSLog.default, type: .info, folderPath)
            
            self.uploadScan(folderURL: folderURL) { success in
                if success {
                    os_log("✅ [UPLOAD NOTIFICATION] Successfully uploaded scan to backend immediately after completion", log: OSLog.default, type: .info)
                    // Keep local data - do not delete after successful upload
                    // Update status to uploaded but preserve local files
                    _ = ScanLocalStorage.shared.updateScanStatus("uploaded", for: folderURL)
                    os_log("📱 [UPLOAD NOTIFICATION] Keeping local scan data after successful upload: %@", log: OSLog.default, type: .info, folderURL.path)
                } else {
                    os_log("⚠️ [UPLOAD NOTIFICATION] Failed to upload scan to backend immediately after completion", log: OSLog.default, type: .error)
                    // Mark as pending for later retry
                    _ = ScanLocalStorage.shared.updateScanStatus("pending", for: folderURL)
                }
            }
        } else if isOnline && !autoSyncEnabled {
            os_log("⏸️ [UPLOAD NOTIFICATION] Online but auto-sync disabled - scan will remain with initialized status for manual sync", log: OSLog.default, type: .info)
            // When auto-sync is disabled, don't upload automatically - keep initialized status for manual sync
            _ = ScanLocalStorage.shared.updateScanStatus("initialized", for: folderURL)
        } else {
            os_log("📱 [UPLOAD NOTIFICATION] Offline - ignoring upload request, scan will remain with initialized status", log: OSLog.default, type: .info)
            // When offline, we don't attempt upload - the scan should already have initialized status from handleScanComplete
        }
    }
    
    // MARK: - Local Data Management
    
    private func clearAllLocalData(call: FlutterMethodCall, result: @escaping FlutterResult) {
        os_log("🗑️ [CLEAR LOCAL DATA] Starting to clear all local scan data", log: OSLog.default, type: .info)
        
        let localScans = ScanLocalStorage.shared.getAllScans()
        var deletedCount = 0
        var failedCount = 0
        
        for scan in localScans {
            do {
                try FileManager.default.removeItem(at: scan.url)
                deletedCount += 1
                os_log("🗑️ [CLEAR LOCAL DATA] Deleted scan: %@", log: OSLog.default, type: .info, scan.url.path)
            } catch {
                failedCount += 1
                os_log("❌ [CLEAR LOCAL DATA] Failed to delete scan: %@ - Error: %@", log: OSLog.default, type: .error, scan.url.path, error.localizedDescription)
            }
        }
        
        // Clear cache
        invalidateScanCache()
        
        let message = "Deleted \(deletedCount) scans successfully"
        let details = failedCount > 0 ? "Failed to delete \(failedCount) scans" : nil
        
        os_log("📊 [CLEAR LOCAL DATA] Summary - Deleted: %d, Failed: %d", log: OSLog.default, type: .info, deletedCount, failedCount)
        
        result([
            "success": failedCount == 0,
            "deleted_count": deletedCount,
            "failed_count": failedCount,
            "message": message,
            "details": details as Any
        ])
    }
    
    // MARK: - Auto-Sync Settings Management
    
    private func setAutoSyncEnabled(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let enabled = args["enabled"] as? Bool else {
            result(FlutterError(
                code: "INVALID_ARGUMENT",
                message: "Invalid or missing enabled parameter.",
                details: nil
            ))
            return
        }
        
        autoSyncEnabled = enabled
        os_log("📱 [AUTO SYNC] Setting auto-sync enabled: %@", log: OSLog.default, type: .info, enabled ? "YES" : "NO")
        
        // Don't automatically sync when enabling auto-sync - this should be a separate user action
        // Auto-sync will only take effect for new scans or when network comes back online
        
        result("Auto-sync setting updated successfully")
    }
    
    private func getAutoSyncEnabled(result: @escaping FlutterResult) {
        result(["enabled": autoSyncEnabled])
    }
    
    private func syncInitializedScans(result: @escaping FlutterResult) {
        syncInitializedScans { success in
            if success {
                result("Initialized scans synced successfully")
            } else {
                result(FlutterError(
                    code: "SYNC_FAILED",
                    message: "Failed to sync some initialized scans",
                    details: nil
                ))
            }
        }
    }
    
    private func syncInitializedScans(completion: @escaping (Bool) -> Void) {
        os_log("🔄 [SYNC INITIALIZED] Starting sync of initialized scans...", log: OSLog.default, type: .info)
        
        let localScans = ScanLocalStorage.shared.getAllScans()
        let initializedScans = localScans.filter { scan in
            guard let metadata = scan.metadata else { return false }
            return metadata.status == "initialized"
        }
        
        guard !initializedScans.isEmpty else {
            os_log("ℹ️ [SYNC INITIALIZED] No initialized scans to sync", log: OSLog.default, type: .info)
            completion(true)
            return
        }
        
        os_log("📜 [SYNC INITIALIZED] Found %d initialized scans to upload", log: OSLog.default, type: .info, initializedScans.count)
        
        let group = DispatchGroup()
        var syncResults: [(scan: (url: URL, metadata: ScanMetadata?), success: Bool)] = []
        
        for scan in initializedScans {
            guard let metadata = scan.metadata else { continue }
            
            os_log("🚀 [SYNC INITIALIZED] Uploading scan: %@", log: OSLog.default, type: .info, metadata.name)
            
            // Update status to uploading
            _ = ScanLocalStorage.shared.updateScanStatus("uploading", for: scan.url)
            
            group.enter()
            self.uploadScan(folderURL: scan.url) { [weak self] success in
                syncResults.append((scan: scan, success: success))
                
                if success {
                    os_log("✅ [SYNC INITIALIZED] Successfully uploaded: %@", log: OSLog.default, type: .info, metadata.name)
                    
                    // Update status to uploaded after successful manual upload
                    _ = ScanLocalStorage.shared.updateScanStatus("uploaded", for: scan.url)
                    os_log("📱 [SYNC INITIALIZED] Updated scan status to uploaded: %@", log: OSLog.default, type: .info, scan.url.path)
                } else {
                    os_log("❌ [SYNC INITIALIZED] Failed to upload: %@", log: OSLog.default, type: .error, metadata.name)
                    
                    // Revert status back to initialized for retry later
                    _ = ScanLocalStorage.shared.updateScanStatus("initialized", for: scan.url)
                }
                
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            self.invalidateScanCache()
            
            let successCount = syncResults.filter { $0.success }.count
            let failedCount = syncResults.count - successCount
            
            os_log("📊 [SYNC INITIALIZED] Sync completed - Success: %d, Failed: %d", log: OSLog.default, type: .info, successCount, failedCount)
            
            // Notify Flutter about sync completion
            self.channel?.invokeMethod("initializedSyncComplete", arguments: [
                "success": failedCount == 0,
                "successCount": successCount,
                "failedCount": failedCount
            ])
            
            completion(failedCount == 0)
        }
    }
    
    // MARK: - Server-Side Model Processing
    
    private func processModelOnServer(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let scanId = args["scanId"] as? Int else {
            result(FlutterError(
                code: "INVALID_ARGUMENT",
                message: "Invalid or missing scanId for server processing.",
                details: nil
            ))
            return
        }
        
        os_log("🔄 [SERVER PROCESS] Starting server-side processing for scan ID: %d", log: OSLog.default, type: .info, scanId)
        
        processModelOnServer(scanId: scanId) { [weak self] success, message in
            if success {
                os_log("✅ [SERVER PROCESS] Successfully triggered processing for scan ID: %d", log: OSLog.default, type: .info, scanId)
                result(["success": true, "message": message])
            } else {
                os_log("❌ [SERVER PROCESS] Failed to trigger processing for scan ID: %d - %@", log: OSLog.default, type: .error, scanId, message)
                result(FlutterError(
                    code: "PROCESSING_FAILED",
                    message: message,
                    details: nil
                ))
            }
        }
    }
    
    private func processModelOnServer(scanId: Int, completion: @escaping (Bool, String) -> Void) {
        guard let url = URL(string: processAPIURL(scanId: scanId)) else {
            completion(false, "Invalid processing API URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Add authorization header if we have a token
        if let token = readAuthToken(), !token.isEmpty {
            request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Create request body with scan ID
        let requestBody: [String: Any] = [
            "scan_id": scanId,
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(false, "Failed to serialize request body: \(error.localizedDescription)")
            return
        }
        
        // Log the request details
        os_log("🚀 [SERVER PROCESS] POST %@", log: OSLog.default, type: .info, url.absoluteString)
        os_log("📋 [SERVER PROCESS] Headers: %@", log: OSLog.default, type: .info, request.allHTTPHeaderFields?.description ?? "None")
        os_log("📦 [SERVER PROCESS] Body: %@", log: OSLog.default, type: .info, String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "None")
        
        // Make the API call
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                os_log("❌ [SERVER PROCESS] Network error: %@", log: OSLog.default, type: .error, error.localizedDescription)
                completion(false, "Network error: \(error.localizedDescription)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(false, "Invalid response type")
                return
            }
            
            let statusCode = httpResponse.statusCode
            os_log("📥 [SERVER PROCESS] Response status: %d", log: OSLog.default, type: .info, statusCode)
            
            // Log response body for debugging
            if let data = data, let responseString = String(data: data, encoding: .utf8) {
                os_log("📥 [SERVER PROCESS] Response body: %@", log: OSLog.default, type: .info, responseString)
            }
            
            // Check if the request was successful
            if statusCode >= 200 && statusCode < 300 {
                // Try to parse response for any additional info
                var message = "Processing started successfully"
                if let data = data {
                    if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let responseMessage = jsonResponse["message"] as? String {
                            message = responseMessage
                        } else if let status = jsonResponse["status"] as? String {
                            message = "Processing \(status)"
                        }
                    }
                }
                completion(true, message)
            } else {
                // Handle error responses
                var errorMessage = "Server processing failed with status \(statusCode)"
                if let data = data {
                    if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let serverMessage = jsonResponse["error"] as? String {
                            errorMessage = serverMessage
                        } else if let serverMessage = jsonResponse["message"] as? String {
                            errorMessage = serverMessage
                        } else if let detail = jsonResponse["detail"] as? String {
                            errorMessage = detail
                        }
                    }
                }
                completion(false, errorMessage)
            }
        }.resume()
    }
}
