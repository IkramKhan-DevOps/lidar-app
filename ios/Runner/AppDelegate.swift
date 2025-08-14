import UIKit
import Flutter
import os.log
import ARKit
import QuickLook
import UniformTypeIdentifiers
import GoogleMaps
import Network

@available(iOS 13.4, *)
@main
@objc class AppDelegate: FlutterAppDelegate, QLPreviewControllerDataSource, UIDocumentPickerDelegate {
    private var channel: FlutterMethodChannel?
    private var currentUSDZURL: URL?
    private var openFolderResult: FlutterResult?
    private var modelVC: ModelViewController?
    private var scanCache: [(url: URL, metadata: ScanMetadata?)]?
    private let networkMonitor = NWPathMonitor()
    private var isOnline = false
    private let apiBaseURL = "http://192.168.1.2:9000/api/v1" // Assume API base, update as needed
    
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

        GMSServices.provideAPIKey("AIzaSyBGY58NEOvds0GTr8jmvd6TrOu3-W6SSBQ")
        GeneratedPluginRegistrant.register(with: self)

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


            if #available(iOS 13.4, *) {
                switch call.method {
                case "startScan":
                    self.startLiDARScan(result: result)
                case "getSavedScans":
                    self.getSavedScans(call: call, result: result)
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
                case "scanComplete":
                    self.handleScanComplete(call: call, result: result)
                case "uploadScanToBackend":
                    self.handleUploadScanToBackend(call: call, result: result)
                case "downloadZipFile":
                    self.downloadZipFile(call: call, result: result)
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



    private func setupNetworkMonitor() {
            networkMonitor.pathUpdateHandler = { path in
                let wasOffline = !self.isOnline
                self.isOnline = path.status == .satisfied
                if self.isOnline && wasOffline {
                    self.syncLocalToServer { success in
                        if success {
                            os_log("Offline scans synced to server", log: OSLog.default, type: .info)
                        } else {
                            os_log("Failed to sync offline scans", log: OSLog.default, type: .error)
                        }
                    }
                }
            }
            let queue = DispatchQueue(label: "AppDelegateNetworkMonitor")
            networkMonitor.start(queue: queue)
        }

       private func syncLocalToServer(completion: @escaping (Bool) -> Void) {
               let localScans = ScanLocalStorage.shared.getAllScans()
               var syncSuccess = true
               let group = DispatchGroup()

               for local in localScans {
                   if let localMeta = local.metadata, localMeta.status == "pending" || localMeta.status == "failed" {
                       group.enter()
                       self.uploadScan(folderURL: local.url) { success in
                           if success {
                               do {
                                   try FileManager.default.removeItem(at: local.url)
                                   os_log("Deleted local scan after successful upload: %@", log: OSLog.default, type: .info, local.url.path)
                               } catch {
                                   os_log("Failed to delete local scan: %@", log: OSLog.default, type: .error, error.localizedDescription)
                                   syncSuccess = false
                               }
                           } else {
                               syncSuccess = false
                           }
                           group.leave()
                       }
                   }
               }

               group.notify(queue: .main) {
                   self.invalidateScanCache()
                   completion(syncSuccess)
               }
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
                            // Server returns an array of simple items; map to ScanMetadata with safe defaults
                            let generic = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
                            let dateFormatter = ISO8601DateFormatter()
                            let mapped: [ScanMetadata] = generic.map { item in
                                let id = (item["id"] as? Int) ?? 0
                                let title = (item["title"] as? String) ?? ""
                                let created = (item["created_at"] as? String) ?? ISO8601DateFormatter().string(from: Date())
                                let ts = dateFormatter.date(from: created) ?? Date()
                                let imgCount = 0
                                let status = "uploaded"
                                return ScanMetadata(
                                    name: title,
                                    timestamp: ts,
                                    scanID: String(id),
                                    coordinates: nil,
                                    coordinateTimestamps: nil,
                                    locationName: nil,
                                    modelSizeBytes: nil,
                                    imageCount: imgCount,
                                    status: status,
                                    snapshotPath: nil,
                                    durationSeconds: (item["duration"] as? Double)
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
            os_log("Invalid scanComplete arguments: %@", log: OSLog.default, type: .error, String(describing: call.arguments))
            result(FlutterError(
                code: "INVALID_ARGUMENT",
                message: "Invalid or missing folder path in scanComplete.",
                details: nil
            ))
            return
        }

        // Invalidate cache to ensure fresh scan data
        invalidateScanCache()
        os_log("Received scanComplete for folder: %@", log: OSLog.default, type: .info, folderPath)

        // Fetch updated scans and notify Flutter
        getSavedScans { [weak self] scansResult in
            self?.channel?.invokeMethod("scanComplete", arguments: args) { invokeResult in
                if let error = invokeResult as? FlutterError {
                    os_log("Failed to invoke scanComplete: %@", log: OSLog.default, type: .error, error.message ?? "Unknown error")
                }
            }
            // After notifying Flutter, attempt to upload to server if data is complete
            guard let self = self else { return }
            let folderURL = URL(fileURLWithPath: folderPath)
            let metaURL = folderURL.appendingPathComponent("metadata.json")
            let zipURL = folderURL.appendingPathComponent("input_data.zip")
            let fm = FileManager.default
            if fm.fileExists(atPath: metaURL.path) && fm.fileExists(atPath: zipURL.path) {
                os_log("Uploading completed scan to server: %@", log: OSLog.default, type: .info, folderPath)
                self.uploadScan(folderURL: folderURL) { ok in
                    if ok {
                        os_log("Uploaded scan successfully: %@", log: OSLog.default, type: .info, folderPath)
                    } else {
                        os_log("Upload scan failed: %@", log: OSLog.default, type: .error, folderPath)
                    }
                }
            } else {
                os_log("Scan data incomplete; metadata or zip missing for: %@", log: OSLog.default, type: .error, folderPath)
            }
            result("Scan complete notification processed")
        }
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
            scanVC.modalPresentationStyle = .fullScreen
            controller.present(scanVC, animated: true) {
                result("Scan started")
            }
        }
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
            if let meta = try? decoder.decode(ScanMetadata.self, from: metadataData) {
                title = meta.name
                durationSeconds = meta.durationSeconds ?? 0
                modelBytes = meta.modelSizeBytes ?? 0
                locationName = meta.locationName ?? ""
            }
            let payload: [String: Any] = [
                "title": title,
                "description": "Uploaded from iOS app",
                "duration": Int(durationSeconds),
                "area_covered": 0,
                "height": 0,
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
                            // Step 5: Post upload status
                            self.postUploadStatus(scanId: sid, status: "uploaded", errorMessage: nil) { _ in
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
            let ts = meta.coordinateTimestamps ?? []
            let group = DispatchGroup()
            var allOk = true
            for (index, coord) in coords.enumerated() {
                if coord.count < 2 { continue }
                let lat = coord[0]
                let lon = coord[1]
                let altitude = coord.count > 2 ? coord[2] : 0.0
                let accuracy = 0.0
                let timestampSeconds: Double = index < ts.count ? ts[index] : meta.timestamp.timeIntervalSince1970
                let iso = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestampSeconds))

                os_log("📍 [GPS POINTS] Uploading GPS point %d: lat=%.6f, lon=%.6f, alt=%.2f", log: OSLog.default, type: .info, index + 1, lat, lon, altitude)

                guard let url = URL(string: "\(apiBaseURL)/scans/\(scanId)/gps-points/") else { continue }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                if let token = readAuthToken(), !token.isEmpty { req.setValue("Token \(token)", forHTTPHeaderField: "Authorization") }
                let body: [String: Any] = [
                    "scan": scanId,  // Django expects 'scan' field, not 'scan_id'
                    "latitude": lat,
                    "longitude": lon,
                    "altitude": altitude,
                    "accuracy": accuracy,
                    "timestamp": iso
                ]
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                
                // Log the GPS point upload request
                os_log("🚀 [GPS POINTS] POST %@ (Point %d)", log: OSLog.default, type: .info, url.absoluteString, index + 1)
                os_log("📋 [GPS POINTS] Headers: %@", log: OSLog.default, type: .info, req.allHTTPHeaderFields?.description ?? "None")
                os_log("📦 [GPS POINTS] Body: %@", log: OSLog.default, type: .info, String(data: req.httpBody ?? Data(), encoding: .utf8) ?? "None")
                
                group.enter()
                URLSession.shared.dataTask(with: req) { _, response, error in
                    if let error = error { 
                        os_log("❌ [GPS POINTS] Point %d upload failed: %@", log: OSLog.default, type: .error, index + 1, error.localizedDescription)
                        allOk = false 
                    }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    if !(status == 200 || status == 201 || status == 204) { 
                        os_log("❌ [GPS POINTS] Point %d upload failed with status %d", log: OSLog.default, type: .error, index + 1, status)
                        allOk = false 
                    } else {
                        os_log("✅ [GPS POINTS] Point %d uploaded successfully (Status: %d)", log: OSLog.default, type: .info, index + 1, status)
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
            case "uploaded", "processed":
                djangoStatus = "completed"
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
        os_log("📱 [GET SAVED SCANS] Method called", log: OSLog.default, type: .info)
        
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
                    "modelSizeBytes": metadata.modelSizeBytes,
                    "durationSeconds": metadata.durationSeconds ?? 0.0
                ]
                
                if let locationName = metadata.locationName {
                    scanDict["locationName"] = locationName
                }
                
                if let coordinates = metadata.coordinates, !coordinates.isEmpty {
                    scanDict["coordinates"] = coordinates
                }
                
                scanList.append(scanDict)
            }
        }
        
        os_log("📱 [GET SAVED SCANS] Returning %d local scans", log: OSLog.default, type: .info, scanList.count)
        result(scanList)
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

    private func invalidateScanCache() {
        scanCache = nil
        os_log("Invalidated scan cache", log: OSLog.default, type: .info)
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
        self.ensureScanExistsOnBackend(folderURL: folderURL) { [weak self] scanId in
            guard let self = self, let scanId = scanId else {
                os_log("Failed to ensure scan exists on backend for processed scan", log: OSLog.default, type: .error)
                completion(false)
                return
            }
            
            // Upload the processed USDZ model to point-cloud endpoint
            self.uploadProcessedModel(scanId: scanId, usdzURL: usdzURL) { modelUploadSuccess in
                if modelUploadSuccess {
                    // Update upload status to indicate successful processing
                    self.postUploadStatus(scanId: scanId, status: "completed", errorMessage: nil) { statusSuccess in
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
        self.ensureScanExistsOnBackend(folderURL: folderURL) { [weak self] scanId in
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
              let zipData = try? Data(contentsOf: zipURL) else {
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
                result("Scan uploaded successfully to backend")
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
    
    @objc private func handleUploadNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let folderPath = userInfo["folderPath"] as? String else {
            os_log("❌ [UPLOAD NOTIFICATION] Invalid notification data", log: OSLog.default, type: .error)
            return
        }
        
        os_log("🔔 [UPLOAD NOTIFICATION] Received upload request for: %@", log: OSLog.default, type: .info, folderPath)
        
        let folderURL = URL(fileURLWithPath: folderPath)
        let metadataURL = folderURL.appendingPathComponent("metadata.json")
        let zipURL = folderURL.appendingPathComponent("input_data.zip")

        guard FileManager.default.fileExists(atPath: metadataURL.path) && FileManager.default.fileExists(atPath: zipURL.path) else {
            os_log("❌ [UPLOAD NOTIFICATION] Required files not found", log: OSLog.default, type: .error)
            return
        }

        // Trigger the full upload flow immediately
        os_log("🚀 [UPLOAD NOTIFICATION] Starting immediate backend upload for scan: %@", log: OSLog.default, type: .info, folderPath)
        
        self.uploadScan(folderURL: folderURL) { success in
            if success {
                os_log("✅ [UPLOAD NOTIFICATION] Successfully uploaded scan to backend immediately after completion", log: OSLog.default, type: .info)
            } else {
                os_log("⚠️ [UPLOAD NOTIFICATION] Failed to upload scan to backend immediately after completion", log: OSLog.default, type: .error)
            }
        }
    }
}
