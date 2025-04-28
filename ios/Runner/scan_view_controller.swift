import UIKit
import ARKit
import SceneKit
import AVFoundation
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
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arScanner.stopScan()
        // Only clean up if we're not presenting the preview
        if !isPresentingPreview {
            cleanupTemporaryFiles()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Reset the flag when the view reappears
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
        
        var plyHeader = """
        ply
        format ascii 1.0
        comment Generated by ARScanner
        element vertex \(meshes.reduce(0) { $0 + $1.vertices.count })
        property float x
        property float y
        property float z
        element face \(meshes.reduce(0) { $0 + $1.indices.count / 3 })
        property list uchar uint vertex_indices
        end_header\n\n
        """
        
        var vertexOffset = 0
        var plyBody = ""
        
        for mesh in meshes {
            for vertex in mesh.vertices {
                plyBody += "\(vertex.x) \(vertex.y) \(vertex.z)\n"
            }
        }
        
        for mesh in meshes {
            for i in stride(from: 0, to: mesh.indices.count, by: 3) {
                let i0 = mesh.indices[i] + UInt32(vertexOffset)
                let i1 = mesh.indices[i+1] + UInt32(vertexOffset)
                let i2 = mesh.indices[i+2] + UInt32(vertexOffset)
                plyBody += "3 \(i0) \(i1) \(i2)\n"
            }
            vertexOffset += mesh.vertices.count
        }
        
        return plyHeader + plyBody
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
            // Clean up both ZIP and original images
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
        
        // Clear previous file if exists
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try? FileManager.default.removeItem(at: zipURL)
        }
        
        activityIndicator?.startAnimating()
        
        // Perform ZIP creation on a background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Create temporary export folder
                try self.fileManager.createDirectory(at: exportFolderURL, withIntermediateDirectories: true)
                
                // Save model as PLY
                let modelURL = exportFolderURL.appendingPathComponent("model.ply")
                let plyContent = try self.generatePLYContent()
                try plyContent.write(to: modelURL, atomically: true, encoding: .utf8)
                os_log("✅ Wrote PLY model to: %@", log: .default, type: .info, modelURL.path)
                
                // Copy images if they exist
                let imagesFolderURL = documentsURL.appendingPathComponent("ScanCapture")
                if self.fileManager.fileExists(atPath: imagesFolderURL.path) {
                    let destinationImagesURL = exportFolderURL.appendingPathComponent("images")
                    try self.fileManager.copyItem(at: imagesFolderURL, to: destinationImagesURL)
                    os_log("✅ Copied images to: %@", log: .default, type: .info, destinationImagesURL.path)
                } else {
                    os_log("⚠️ No images found at: %@", log: .default, type: .info, imagesFolderURL.path)
                }
                
                // Create ZIP
                try self.fileManager.zipItem(at: exportFolderURL, to: zipURL)
                
                // Clean up temporary folder
                try? self.fileManager.removeItem(at: exportFolderURL)
                
                DispatchQueue.main.async {
                    self.activityIndicator?.stopAnimating()
                    
                    guard FileManager.default.fileExists(atPath: zipURL.path) else {
                        self.showExportError("Failed to create ZIP file")
                        return
                    }
                    
                    // Store reference
                    self.currentExportURL = zipURL
                    
                    // Start accessing the security-scoped resource
                    let didStartAccessing = zipURL.startAccessingSecurityScopedResource()
                    
                    // Present share sheet with custom activity item
                    let activityVC = UIActivityViewController(
                        activityItems: [NonCollaborativeFileActivityItem(fileURL: zipURL)],
                        applicationActivities: nil
                    )
                    
                    // Base list of excluded activities (compatible with iOS 13.4+)
                    var excludedActivities: [UIActivity.ActivityType] = [
                        .addToReadingList,
                        .assignToContact,
                        .markupAsPDF,
                        .openInIBooks,
                        .postToWeibo,
                        .print,
                        .saveToCameraRoll,
                        .postToVimeo,
                        .postToFlickr,
                        .postToTencentWeibo,
                        .postToFacebook,
                        .postToTwitter,
                        .airDrop,
                        .copyToPasteboard,
                        .mail,
                        .message
                    ]
                    
                    // Add iOS 16.0+ specific activities if available
                    if #available(iOS 16.0, *) {
                        excludedActivities.append(contentsOf: [
                            .collaborationCopyLink,
                            .collaborationInviteWithLink
                        ])
                    }
                    
                    activityVC.excludedActivityTypes = excludedActivities
                    
                    // Configure popover for iPad
                    if let popover = activityVC.popoverPresentationController {
                        popover.sourceView = self.controlPanel.exportButton
                        popover.sourceRect = self.controlPanel.exportButton.bounds
                    }
                    
                    // Handle completion - THIS is where we clean up everything
                    activityVC.completionWithItemsHandler = { [weak self] _, completed, _, _ in
                        // Stop accessing the security-scoped resource
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
        // Removed cleanupTemporaryFiles() to prevent clearing images on stop
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
