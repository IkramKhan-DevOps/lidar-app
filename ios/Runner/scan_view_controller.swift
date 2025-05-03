import UIKit
import ARKit
import SceneKit
import AVFoundation
import SSZipArchive
import os.log

// Custom activity item source to prevent collaboration features
@available(iOS 13.4, *)
class NonCollaborativeFileActivityItem: NSObject, UIActivityItemSource {
    let fileURL: URL
    
    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return fileURL
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return fileURL
    }
    
    // Explicitly disable collaboration features
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        return "public.zip-archive"
    }
}

@available(iOS 13.4, *)
class ScanViewController: UIViewController {
    
    // MARK: - Components
    private let arScanner = ARScanner()
    let captureManager = ScanCaptureManager()
    private let controlPanel = ControlPanel()
    private let fileManager = FileManager.default
    
    // Current export state
    private var currentExportURL: URL?
    private var activityIndicator: UIActivityIndicatorView?
    
    // Flag to track if we're presenting the preview
    private var isPresentingPreview: Bool = false
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
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
            cleanupTemporaryFiles()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isPresentingPreview = false
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .black
        
        view.addSubview(arScanner.view)
        arScanner.view.frame = view.bounds
        
        view.addSubview(controlPanel)
        controlPanel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controlPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            controlPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            controlPanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
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
    
    // MARK: - Permission Handling
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
    
    // MARK: - Data Management
    private func saveCapturedMeshes() throws -> URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent("scan_\(Date().timeIntervalSince1970).json")
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(arScanner.getCapturedMeshes())
        try data.write(to: fileURL, options: [.atomicWrite, .completeFileProtection])
        
        return fileURL
    }
    
    private func generatePLYContent() throws -> String {
        let meshes = arScanner.getCapturedMeshes()
        guard !meshes.isEmpty else {
            throw NSError(domain: "No meshes", code: 0, userInfo: nil)
        }
        
        var vertexOffset = 0
        var combinedVertices: [SIMD3<Float>] = []
        var combinedNormals: [SIMD3<Float>] = []
        var combinedIndices: [UInt32] = []
        
        for mesh in meshes {
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
    
    private func savePLYFile(content: String) throws -> URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent("scan_\(Date().timeIntervalSince1970).ply")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
    
    private func shareFile(_ fileURL: URL) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            showAlert(title: "Export Error", message: "File not found at path: \(fileURL.path)")
            return
        }
        
        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let activityVC = UIActivityViewController(activityItems: [NonCollaborativeFileActivityItem(fileURL: fileURL)], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = controlPanel
        activityVC.popoverPresentationController?.sourceRect = controlPanel.bounds
        
        activityVC.completionWithItemsHandler = { [weak self] _, completed, _, _ in
            if completed {
                self?.cleanupAfterExport()
            }
        }
        
        present(activityVC, animated: true)
    }
    
    // MARK: - File Cleanup
    private func cleanupTemporaryFiles() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.captureManager.cleanupCaptureDirectory()
            os_log("Cleaned up temporary capture files", log: OSLog.default, type: .info)
        }
    }
    
    private func cleanupAfterExport() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            if let url = self?.currentExportURL {
                try? FileManager.default.removeItem(at: url)
                self?.currentExportURL = nil
            }
            self?.captureManager.cleanupCaptureDirectory()
            os_log("Cleaned up all files after export", log: OSLog.default, type: .info)
        }
    }
    
    private func cleanupExportedFile(_ fileURL: URL) {
        DispatchQueue.global(qos: .utility).async {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
                os_log("Deleted exported file", log: OSLog.default, type: .info)
            }
        }
    }
    
    // MARK: - UI Helpers
    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }
    
    private func showExportError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.activityIndicator?.stopAnimating()
            let alert = UIAlertController(title: "Export Failed", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self?.present(alert, animated: true)
        }
    }
    
    private func showPreview() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isPresentingPreview = true
            let previewVC = ModelViewController()
            previewVC.capturedMeshes = self.arScanner.getCapturedMeshes()
            previewVC.modalPresentationStyle = .fullScreen
            self.present(previewVC, animated: true)
        }
    }
    
    // MARK: - Export Methods
    private func exportAsZIP() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let zipURL = documentsURL.appendingPathComponent("ExportedScan_\(UUID().uuidString).zip")
        let exportFolderURL = documentsURL.appendingPathComponent("ScanExport_\(UUID().uuidString)")
        
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try? FileManager.default.removeItem(at: zipURL)
        }
        
        activityIndicator?.startAnimating()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try self.fileManager.createDirectory(at: exportFolderURL, withIntermediateDirectories: true)
                
                let modelURL = exportFolderURL.appendingPathComponent("model.ply")
                let plyContent = try self.generatePLYContent()
                try plyContent.write(to: modelURL, atomically: true, encoding: .utf8)
                
                let imagesFolderURL = documentsURL.appendingPathComponent("ScanCapture")
                if self.fileManager.fileExists(atPath: imagesFolderURL.path) {
                    let destinationImagesURL = exportFolderURL.appendingPathComponent("images")
                    try self.fileManager.copyItem(at: imagesFolderURL, to: destinationImagesURL)
                }
                
                let success = SSZipArchive.createZipFile(atPath: zipURL.path, withContentsOfDirectory: exportFolderURL.path)
                if !success {
                    throw NSError(domain: "SSZipArchive", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create ZIP file"])
                }
                
                try? self.fileManager.removeItem(at: exportFolderURL)
                
                DispatchQueue.main.async {
                    self.activityIndicator?.stopAnimating()
                    
                    guard FileManager.default.fileExists(atPath: zipURL.path) else {
                        self.showExportError("Failed to create ZIP file")
                        return
                    }
                    
                    self.currentExportURL = zipURL
                    let didStartAccessing = zipURL.startAccessingSecurityScopedResource()
                    
                    let activityVC = UIActivityViewController(
                        activityItems: [NonCollaborativeFileActivityItem(fileURL: zipURL)],
                        applicationActivities: nil
                    )
                    
                    var excludedActivities: [UIActivity.ActivityType] = [
                        .addToReadingList, .assignToContact, .markupAsPDF,
                        .openInIBooks, .postToWeibo, .print, .saveToCameraRoll,
                        .postToVimeo, .postToFlickr, .postToTencentWeibo,
                        .postToFacebook, .postToTwitter, .airDrop, .copyToPasteboard,
                        .mail, .message
                    ]
                    
                    if #available(iOS 16.0, *) {
                        excludedActivities.append(contentsOf: [
                            .collaborationCopyLink, .collaborationInviteWithLink
                        ])
                    }
                    
                    activityVC.excludedActivityTypes = excludedActivities
                    
                    if let popover = activityVC.popoverPresentationController {
                        popover.sourceView = self.controlPanel.exportButton
                        popover.sourceRect = self.controlPanel.exportButton.bounds
                    }
                    
                    activityVC.completionWithItemsHandler = { [weak self] _, completed, _, _ in
                        if didStartAccessing {
                            zipURL.stopAccessingSecurityScopedResource()
                        }
                        if completed {
                            self?.cleanupAfterExport()
                        }
                    }
                    
                    self.present(activityVC, animated: true)
                }
            } catch {
                DispatchQueue.main.async {
                    self.activityIndicator?.stopAnimating()
                    self.showExportError(error.localizedDescription)
                }
            }
        }
    }
    
    private func exportAsJSON() {
        do {
            let fileURL = try saveCapturedMeshes()
            shareFile(fileURL)
            cleanupAfterExport()
        } catch {
            showAlert(title: "Export Error", message: error.localizedDescription)
        }
    }
    
    private func exportAsPLY() {
        activityIndicator?.startAnimating()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let plyContent = try self.generatePLYContent()
                let fileURL = try self.savePLYFile(content: plyContent)
                
                DispatchQueue.main.async {
                    self.activityIndicator?.stopAnimating()
                    self.shareFile(fileURL)
                    self.cleanupAfterExport()
                }
            } catch {
                DispatchQueue.main.async {
                    self.activityIndicator?.stopAnimating()
                    self.showAlert(title: "Export Error", message: error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - ARScannerDelegate
@available(iOS 13.4, *)
extension ScanViewController: ARScannerDelegate {
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
            self.controlPanel.updateUIForScanningState(isScanning: false,
                                                     hasMeshes: !scanner.getCapturedMeshes().isEmpty)
        }
    }
    
    func arScannerDidStartScanning(_ scanner: ARScanner) {
        DispatchQueue.main.async {
            self.controlPanel.updateUIForScanningState(isScanning: true, hasMeshes: false)
        }
    }
    
    func arScanner(_ scanner: ARScanner, showAlertWithTitle title: String, message: String) {
        showAlert(title: title, message: message)
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
                message: "Scan stopped. You've reached the 500MB storage limit."
            )
        }
    }
}

// MARK: - ControlPanelDelegate
@available(iOS 13.4, *)
extension ScanViewController: ControlPanelDelegate {
    func controlPanelDidTapStart(_ panel: ControlPanel) {
        arScanner.startScan()
    }
    
    func controlPanelDidTapStop(_ panel: ControlPanel) {
        arScanner.stopScan()
    }
    
    func controlPanelDidTapRestart(_ panel: ControlPanel) {
        arScanner.restartScan()
        cleanupTemporaryFiles()
        if let url = currentExportURL {
            cleanupExportedFile(url)
            currentExportURL = nil
        }
    }
    
    func controlPanelDidTapPreview(_ panel: ControlPanel) {
        showPreview()
    }
    
    func controlPanel(_ panel: ControlPanel, didRequestExportAs format: ExportFormat) {
        switch format {
        case .json:
            exportAsJSON()
        case .ply:
            exportAsPLY()
        case .zip:
            exportAsZIP()
        }
    }
}
