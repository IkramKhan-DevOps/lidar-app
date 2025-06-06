import UIKit
import SceneKit
import SSZipArchive
import os.log
import simd

@available(iOS 13.4, *)
class ModelViewController: UIViewController {
    
    // MARK: - Properties
    var capturedMeshes: [CapturedMesh] = []
    private let sceneView = SCNView()
    
    // MARK: - UI Components
    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Close", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        button.backgroundColor = UIColor.systemGray.withAlphaComponent(0.8)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        button.frame = CGRect(x: 20, y: 50, width: 100, height: 44)
        return button
    }()
    
    private lazy var exportButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Export ZIP", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.addTarget(self, action: #selector(exportTapped), for: .touchUpInside)
        button.frame = CGRect(x: 130, y: 50, width: 120, height: 44)
        return button
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
        view.addSubview(exportButton)
        sceneView.frame = view.bounds
    }
    
    private func setupScene() {
        let scene = SCNScene()
        for mesh in capturedMeshes {
            // Convert SIMD3<Float> to SCNVector3 for vertices and normals
            let vertices = mesh.vertices.map { SCNVector3($0.x, $0.y, $0.z) }
            let normals = mesh.normals.map { SCNVector3($0.x, $0.y, $0.z) }
            
            // Create geometry sources
            let vertexSource = SCNGeometrySource(vertices: vertices)
            let normalSource = SCNGeometrySource(normals: normals)
            
            // Create geometry element
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
            
            // Create geometry
            let geometry = SCNGeometry(
                sources: [vertexSource, normalSource],
                elements: [element]
            )
            
            let node = SCNNode(geometry: geometry)
            
            // Handle transform (support [[Float]] or simd_float4x4)
            if let transformArray = mesh.transform as? [[Float]], transformArray.count == 4, transformArray.allSatisfy({ $0.count == 4 }) {
                node.simdTransform = simd_float4x4(
                    SIMD4<Float>(transformArray[0]),
                    SIMD4<Float>(transformArray[1]),
                    SIMD4<Float>(transformArray[2]),
                    SIMD4<Float>(transformArray[3])
                )
            } else if let transformMatrix = mesh.transform as? simd_float4x4 {
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
        dismiss(animated: true)
    }
    
    @objc private func exportTapped() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let zipURL = documentsURL.appendingPathComponent("ModelExport_\(UUID().uuidString).zip")
        
        do {
            try exportDataAsZip(to: zipURL)
            os_log("✅ Created ZIP at: %@", log: .default, type: .info, zipURL.path)
            
            let activityVC = UIActivityViewController(
                activityItems: [NonCollaborativeFileActivityItem(fileURL: zipURL)],
                applicationActivities: nil
            )
            activityVC.popoverPresentationController?.sourceView = exportButton
            activityVC.popoverPresentationController?.sourceRect = exportButton.bounds
            activityVC.excludedActivityTypes = [
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
            if #available(iOS 16.0, *) {
                activityVC.excludedActivityTypes?.append(contentsOf: [
                    .collaborationCopyLink,
                    .collaborationInviteWithLink
                ])
            }
            
            activityVC.completionWithItemsHandler = { _, completed, _, _ in
                if completed {
                    try? FileManager.default.removeItem(at: zipURL)
                    os_log("✅ Cleaned up ZIP file: %@", log: .default, type: .info, zipURL.path)
                }
            }
            
            present(activityVC, animated: true)
        } catch {
            os_log("❌ Failed to export ZIP: %@", log: .default, type: .error, error.localizedDescription)
            let alert = UIAlertController(
                title: "Export Failed",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
    
    // MARK: - Export
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
    
    func exportDataAsZip(to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Create temp directory
        let exportFolderURL = documentsURL.appendingPathComponent("ScanExport_\(UUID().uuidString)")
        
        do {
            try fileManager.createDirectory(at: exportFolderURL, withIntermediateDirectories: true)
            
            // Save model as PLY
            let modelURL = exportFolderURL.appendingPathComponent("model.ply")
            let plyContent = try generatePLYContent()
            try plyContent.write(to: modelURL, atomically: true, encoding: .utf8)
            os_log("✅ Saved model PLY at: %@", log: .default, type: .info, modelURL.path)
            
            // Copy images folder
            let imagesFolderURL = documentsURL.appendingPathComponent("ScanCapture")
            if fileManager.fileExists(atPath: imagesFolderURL.path) {
                let destinationImagesURL = exportFolderURL.appendingPathComponent("images")
                try fileManager.copyItem(at: imagesFolderURL, to: destinationImagesURL)
                os_log("✅ Copied images to: %@", log: .default, type: .info, destinationImagesURL.path)
            } else {
                os_log("⚠️ No images found at: %@", log: .default, type: .info, imagesFolderURL.path)
            }
            
            // Create ZIP using SSZipArchive
            let success = SSZipArchive.createZipFile(atPath: destinationURL.path, withContentsOfDirectory: exportFolderURL.path)
            if !success {
                throw NSError(domain: "SSZipArchive", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create ZIP file"])
            }
            os_log("✅ Created ZIP at: %@", log: .default, type: .info, destinationURL.path)
            
            // Clean up TEMP export folder
            try fileManager.removeItem(at: exportFolderURL)
            os_log("✅ Cleaned up temp export folder: %@", log: .default, type: .info, exportFolderURL.path)
        } catch {
            try? fileManager.removeItem(at: exportFolderURL)
            os_log("❌ Failed to create ZIP: %@", log: .default, type: .error, error.localizedDescription)
            throw error
        }
    }
}
