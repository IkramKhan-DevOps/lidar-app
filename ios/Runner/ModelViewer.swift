/*
 * ModelViewer.swift
 * Copyright (c) 2025 Your Name
 *
 * This file uses SSZipArchive, licensed under the Apache License 2.0 (or MIT, depending on version).
 * See https://github.com/ZipArchive/ZipArchive for license details.
 */

import UIKit
import SceneKit
import SSZipArchive
import os.log
import simd
import QuickLook

@available(iOS 13.4, *)
class ModelViewController: UIViewController, QLPreviewControllerDataSource, UIDocumentPickerDelegate {
    
    // MARK: - Properties
    var capturedMeshes: [CapturedMesh] = []
    private let sceneView = SCNView()
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var modelUrl: URL?
    private var downloadedFileURL: URL?
    
    // MARK: - UI Components
    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Close", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        button.backgroundColor = UIColor.systemGray.withAlphaComponent(0.8)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.3
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var processButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Process", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.3
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        button.addTarget(self, action: #selector(processTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var downloadButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Download", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        button.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.8)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.3
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        button.addTarget(self, action: #selector(downloadTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true // Hidden until USDZ is loaded
        return button
    }()
    
    private lazy var shareButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Share", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        button.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.8)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.3
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        button.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true // Hidden until USDZ is loaded
        return button
    }()
    
    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.text = ""
        label.textColor = .white
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupScene()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .black
        view.addSubview(sceneView)
        view.addSubview(closeButton)
        view.addSubview(processButton)
        view.addSubview(downloadButton)
        view.addSubview(shareButton)
        view.addSubview(statusLabel)
        view.addSubview(loadingIndicator)
        
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 100),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            
            processButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            processButton.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 16),
            processButton.widthAnchor.constraint(equalToConstant: 120),
            processButton.heightAnchor.constraint(equalToConstant: 44),
            
            downloadButton.topAnchor.constraint(equalTo: processButton.bottomAnchor, constant: 16),
            downloadButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            downloadButton.widthAnchor.constraint(equalToConstant: 100),
            downloadButton.heightAnchor.constraint(equalToConstant: 44),
            
            shareButton.topAnchor.constraint(equalTo: processButton.bottomAnchor, constant: 16),
            shareButton.leadingAnchor.constraint(equalTo: downloadButton.trailingAnchor, constant: 16),
            shareButton.widthAnchor.constraint(equalToConstant: 100),
            shareButton.heightAnchor.constraint(equalToConstant: 44),
            
            statusLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            statusLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func setupScene() {
        let scene = SCNScene()
        for mesh in capturedMeshes {
            let vertices = mesh.vertices.map { SCNVector3($0.x, $0.y, $0.z) }
            let normals = mesh.normals.map { SCNVector3($0.x, $0.y, $0.z) }
            
            let vertexSource = SCNGeometrySource(vertices: vertices)
            let normalSource = SCNGeometrySource(normals: normals)
            
            let indexData = Data(
                bytes: mesh.indices,
                count: mesh.indices.count * MemoryLayout<UInt32>.size
            )
            let element = SCNGeometryElement(
                data: indexData,
                primitiveType: .triangles,
                primitiveCount: mesh.indices.count / 3,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )
            
            let geometry = SCNGeometry(
                sources: [vertexSource, normalSource],
                elements: [element]
            )
            
            let node = SCNNode(geometry: geometry)
            
            if let transformArray = mesh.transform as? [[Float]], transformArray.count == 4, transformArray.allSatisfy({ $0.count == 4 }) {
                let matrix = simd_float4x4(
                    SIMD4<Float>(transformArray[0]),
                    SIMD4<Float>(transformArray[1]),
                    SIMD4<Float>(transformArray[2]),
                    SIMD4<Float>(transformArray[3])
                )
                node.simdTransform = matrix
            } else if mesh.transform is simd_float4x4, let transformMatrix = mesh.transform as? simd_float4x4 {
                node.simdTransform = transformMatrix
            } else {
                os_log("⚠️ Invalid transform format for mesh", log: .default, type: .error)
                node.simdTransform = matrix_identity_float4x4
            }
            
            scene.rootNode.addChildNode(node)
        }
        sceneView.scene = scene
        sceneView.allowsCameraControl = true
        sceneView.autoenablesDefaultLighting = true
        sceneView.backgroundColor = .black
    }
    
    // MARK: - Actions
    @objc private func closeTapped() {
        let alert = UIAlertController(
            title: "Close Viewer",
            message: "Are you sure you want to close the model viewer?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Close", style: .destructive) { _ in
            self.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
    
    @objc private func processTapped() {
        processButton.isEnabled = false
        processButton.setTitle("Processing...", for: .normal)
        loadingIndicator.startAnimating()
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let zipURL = documentsURL.appendingPathComponent("ModelProcess_\(UUID().uuidString).zip")
        
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            guard let self = self else { return }
            os_log("⚠️ Background task expired", log: .default, type: .error)
            DispatchQueue.main.async {
                self.showErrorAlert(message: "Processing timed out due to app suspension. Please try again.")
                self.processButton.isEnabled = true
                self.processButton.setTitle("Process", for: .normal)
                self.loadingIndicator.stopAnimating()
                self.statusLabel.text = ""
                self.endBackgroundTask()
            }
        }
        
        do {
            try exportDataAsZip(to: zipURL)
        } catch {
            os_log("❌ Failed to process: %@", log: .default, type: .error, error.localizedDescription)
            DispatchQueue.main.async {
                self.showErrorAlert(message: error.localizedDescription)
                self.processButton.isEnabled = true
                self.processButton.setTitle("Process", for: .normal)
                self.loadingIndicator.stopAnimating()
                self.statusLabel.text = ""
                self.endBackgroundTask()
            }
        }
    }
    
    @objc private func downloadTapped() {
        guard let usdzURL = downloadedFileURL else {
            showErrorAlert(message: "No USDZ file available to download.")
            return
        }
        
        let documentPicker = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .exportToService)
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
    
    // MARK: - Processing
    private func processZipFile(at zipURL: URL) throws {
        guard let zipData = try? Data(contentsOf: zipURL) else {
            throw NSError(domain: "FileError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to read ZIP file"])
        }
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 1800
        let session = URLSession(configuration: configuration)
        
        let url = URL(string: "http://213.73.97.120/api/process")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
        request.httpBody = zipData
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                self?.endBackgroundTask()
                return
            }
            
            DispatchQueue.main.async {
                self.processButton.isEnabled = true
                self.processButton.setTitle("Process", for: .normal)
                self.loadingIndicator.stopAnimating()
            }
            
            if let error = error {
                os_log("❌ API request failed: %@", log: .default, type: .error, error.localizedDescription)
                DispatchQueue.main.async {
                    self.showErrorAlert(message: "API request failed: \(error.localizedDescription)")
                    self.statusLabel.text = "Processing failed."
                    self.endBackgroundTask()
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                os_log("❌ API returned non-200 status: %d", log: .default, type: .error, statusCode)
                DispatchQueue.main.async {
                    self.showErrorAlert(message: "API returned status code: \(statusCode)")
                    self.statusLabel.text = "Processing failed."
                    self.endBackgroundTask()
                }
                return
            }
            
            guard let data = data else {
                os_log("❌ No data received from API", log: .default, type: .error)
                DispatchQueue.main.async {
                    self.showErrorAlert(message: "No data received from API")
                    self.statusLabel.text = "Processing failed."
                    self.endBackgroundTask()
                }
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                guard let modelUrlString = json?["modelUrl"] as? String,
                      let modelUrl = URL(string: modelUrlString) else {
                    os_log("❌ Invalid model URL in response", log: .default, type: .error)
                    DispatchQueue.main.async {
                        self.showErrorAlert(message: "Invalid model URL in response")
                        self.statusLabel.text = "Processing failed."
                        self.endBackgroundTask()
                    }
                    return
                }
                
                self.modelUrl = modelUrl
                self.downloadAndDisplayModel(from: modelUrl)
            } catch {
                os_log("❌ Failed to parse API response: %@", log: .default, type: .error, error.localizedDescription)
                DispatchQueue.main.async {
                    self.showErrorAlert(message: "Failed to parse API response: \(error.localizedDescription)")
                    self.statusLabel.text = "Processing failed."
                    self.endBackgroundTask()
                }
            }
        }
        task.resume()
        
        try? FileManager.default.removeItem(at: zipURL)
        os_log("✅ Cleaned up ZIP file: %@", log: .default, type: .info, zipURL.path)
    }
    
    private func downloadAndDisplayModel(from modelUrl: URL) {
        DispatchQueue.main.async {
            self.statusLabel.text = "Downloading model..."
            self.loadingIndicator.startAnimating()
        }
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 600
        let session = URLSession(configuration: configuration)
        
        let task = session.downloadTask(with: modelUrl) { [weak self] tempURL, response, error in
            guard let self = self else {
                self?.endBackgroundTask()
                return
            }
            
            DispatchQueue.main.async {
                self.loadingIndicator.stopAnimating()
            }
            
            if let error = error {
                os_log("❌ Failed to download model: %@", log: .default, type: .error, error.localizedDescription)
                DispatchQueue.main.async {
                    self.showErrorAlertWithLink(message: "Failed to download model: \(error.localizedDescription)")
                    self.statusLabel.text = "Model download failed."
                    self.endBackgroundTask()
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                os_log("❌ Model download returned non-200 status: %d", log: .default, type: .error, statusCode)
                DispatchQueue.main.async {
                    self.showErrorAlertWithLink(message: "Model download failed with status: \(statusCode)")
                    self.statusLabel.text = "Model download failed."
                    self.endBackgroundTask()
                }
                return
            }
            
            guard let tempURL = tempURL else {
                os_log("❌ No file URL for downloaded model", log: .default, type: .error)
                DispatchQueue.main.async {
                    self.showErrorAlertWithLink(message: "No file URL for downloaded model")
                    self.statusLabel.text = "Model download failed."
                    self.endBackgroundTask()
                }
                return
            }
            
            let fileManager = FileManager.default
            let sanitizedURL = fileManager.temporaryDirectory.appendingPathComponent("Model_\(UUID().uuidString).usdz")
            do {
                try fileManager.moveItem(at: tempURL, to: sanitizedURL)
                
                if try self.validateUSDZFile(at: sanitizedURL) {
                    DispatchQueue.main.async {
                        do {
                            let scene = try SCNScene(url: sanitizedURL, options: nil)
                            self.sceneView.scene = scene
                            self.statusLabel.text = "Model loaded successfully."
                            self.downloadedFileURL = sanitizedURL
                            self.downloadButton.isHidden = false
                            self.shareButton.isHidden = false
                            os_log("✅ Successfully loaded and displayed USDZ model", log: .default, type: .info)
                            self.endBackgroundTask()
                        } catch {
                            os_log("❌ Failed to load USDZ model with SceneKit: %@", log: .default, type: .error, error.localizedDescription)
                            self.downloadedFileURL = sanitizedURL
                            self.downloadButton.isHidden = false
                            self.shareButton.isHidden = false
                            let previewController = QLPreviewController()
                            previewController.dataSource = self
                            self.present(previewController, animated: true) {
                                self.statusLabel.text = "Model loaded in Quick Look."
                                os_log("✅ Loaded USDZ model in QLPreviewController", log: .default, type: .info)
                                self.endBackgroundTask()
                            }
                        }
                    }
                } else {
                    os_log("❌ Invalid USDZ file format", log: .default, type: .error)
                    DispatchQueue.main.async {
                        self.showErrorAlertWithLink(message: "Invalid USDZ file format")
                        self.statusLabel.text = "Model download failed."
                        try? fileManager.removeItem(at: sanitizedURL)
                        self.endBackgroundTask()
                    }
                }
            } catch {
                os_log("❌ Failed to move temporary file: %@", log: .default, type: .error, error.localizedDescription)
                DispatchQueue.main.async {
                    self.showErrorAlertWithLink(message: "Failed to process downloaded file: \(error.localizedDescription)")
                    self.statusLabel.text = "Model download failed."
                    try? fileManager.removeItem(at: sanitizedURL)
                    self.endBackgroundTask()
                }
            }
        }
        task.resume()
    }
    
    // MARK: - QLPreviewControllerDataSource
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return downloadedFileURL != nil ? 1 : 0
    }
    
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return downloadedFileURL! as NSURL
    }
    
    // MARK: - UIDocumentPickerDelegate
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        statusLabel.text = "Model saved successfully."
        generateHapticFeedback()
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        statusLabel.text = "Download cancelled."
    }
    
    // MARK: - USDZ Validation
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
            os_log("❌ USDZ validation failed: %@", log: .default, type: .error, error.localizedDescription)
            return false
        }
    }
    
    private func showErrorAlert(message: String) {
        let alert = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
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
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    // MARK: - ZIP Creation
    func exportDataAsZip(to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exportFolderURL = documentsURL.appendingPathComponent("ScanExport_\(UUID().uuidString)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try fileManager.createDirectory(at: exportFolderURL, withIntermediateDirectories: true)
                
                let modelURL = exportFolderURL.appendingPathComponent("model.ply")
                let plyContent = try self.generatePLYContent()
                try plyContent.write(to: modelURL, atomically: true, encoding: .utf8)
                os_log("✅ Saved model PLY at: %@", log: .default, type: .info, modelURL.path)
                
                let imagesFolderURL = documentsURL.appendingPathComponent("ScanCapture")
                if fileManager.fileExists(atPath: imagesFolderURL.path) {
                    let destinationImagesURL = exportFolderURL.appendingPathComponent("images")
                    try fileManager.copyItem(at: imagesFolderURL, to: destinationImagesURL)
                    os_log("✅ Copied images to: %@", log: .default, type: .info, destinationImagesURL.path)
                } else {
                    os_log("⚠️ No images found at: %@", log: .default, type: .info, imagesFolderURL.path)
                }
                
                let success = SSZipArchive.createZipFile(atPath: destinationURL.path, withContentsOfDirectory: exportFolderURL.path)
                if !success {
                    throw NSError(domain: "SSZipArchive", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create ZIP file"])
                }
                os_log("✅ Created ZIP at: %@", log: .default, type: .info, destinationURL.path)
                
                try fileManager.removeItem(at: exportFolderURL)
                os_log("✅ Cleaned up temp export folder: %@", log: .default, type: .info, exportFolderURL.path)
                
                DispatchQueue.main.async {
                    do {
                        let zipAttributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
                        let zipSizeBytes = zipAttributes[.size] as? Int64 ?? 0
                        let zipSizeMB = Double(zipSizeBytes) / (1024 * 1024)
                        let estimatedMinutes = (zipSizeMB / 50.0) * 2.0
                        let estimatedTimeText = String(format: "%.1f", estimatedMinutes)
                        self.statusLabel.text = String(format: "ZIP file created (%.2f MB). Processing may take ~%@ minutes...", zipSizeMB, estimatedTimeText)
                        try self.processZipFile(at: destinationURL)
                    } catch {
                        os_log("❌ Failed to process ZIP: %@", log: .default, type: .error, error.localizedDescription)
                        DispatchQueue.main.async {
                            self.showErrorAlert(message: error.localizedDescription)
                            self.processButton.isEnabled = true
                            self.processButton.setTitle("Process", for: .normal)
                            self.loadingIndicator.stopAnimating()
                            self.statusLabel.text = ""
                            self.endBackgroundTask()
                        }
                    }
                }
            } catch {
                try? fileManager.removeItem(at: exportFolderURL)
                os_log("❌ Failed to create ZIP: %@", log: .default, type: .error, error.localizedDescription)
                DispatchQueue.main.async {
                    self.showErrorAlert(message: error.localizedDescription)
                    self.processButton.isEnabled = true
                    self.processButton.setTitle("Process", for: .normal)
                    self.loadingIndicator.stopAnimating()
                    self.statusLabel.text = ""
                    self.endBackgroundTask()
                }
            }
        }
    }
    
    private func generatePLYContent() throws -> String {
        guard !capturedMeshes.isEmpty else {
            throw NSError(domain: "No meshes", code: 0, userInfo: nil)
        }
        
        var vertexOffset = 0
        var combinedVertices: [SIMD3<Float>] = []
        var combinedNormals: [SIMD3<Float>] = []
        var combinedIndices: [UInt32] = []
        
        for mesh in capturedMeshes {
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
    
    // MARK: - Haptic Feedback
    private func generateHapticFeedback(_ type: UINotificationFeedbackGenerator.FeedbackType = .success) {
        let feedbackGenerator = UINotificationFeedbackGenerator()
        feedbackGenerator.prepare()
        feedbackGenerator.notificationOccurred(type)
    }
}
