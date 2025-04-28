import UIKit
import SceneKit
import ZIPFoundation
import os.log

class ModelViewController: UIViewController {
    
    // MARK: - Properties
    var capturedMeshes: [CapturedMesh] = []
    
    // MARK: - UI Components
    private lazy var sceneView: SCNView = {
        let view = SCNView()
        view.backgroundColor = .black
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = true
        view.defaultCameraController.inertiaEnabled = true
        view.defaultCameraController.maximumVerticalAngle = 90
        view.defaultCameraController.minimumVerticalAngle = -90
        return view
    }()
    
    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Close", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        button.backgroundColor = UIColor.systemRed.withAlphaComponent(0.8)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        button.frame = CGRect(x: 20, y: 50, width: 80, height: 44)
        return button
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadModel()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }
    
    private func setupUI() {
        view.backgroundColor = .black
        view.addSubview(sceneView)
        view.addSubview(closeButton)
        sceneView.frame = view.bounds
    }
    
    // MARK: - Model Loading
    private func loadModel() {
        let combinedNode = SCNNode()
        
        for mesh in capturedMeshes {
            let geometry = createGeometry(from: mesh)
            let node = SCNNode(geometry: geometry)
            node.simdTransform = mesh.getTransform()
            combinedNode.addChildNode(node)
        }
        
        sceneView.scene = SCNScene()
        sceneView.scene?.rootNode.addChildNode(combinedNode)
        centerModel(targetNode: combinedNode)
    }
    
    private func createGeometry(from mesh: CapturedMesh) -> SCNGeometry {
        let vertices = mesh.vertices.map { SCNVector3($0) }
        let vertexSource = SCNGeometrySource(vertices: vertices)
        
        let element = SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)
        
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white.withAlphaComponent(0.8)
        material.lightingModel = .physicallyBased
        
        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
        geometry.materials = [material]
        return geometry
    }
    
    private func centerModel(targetNode: SCNNode) {
        let (minVec, maxVec) = targetNode.boundingBox
        
        let bound = SCNVector3(
            x: maxVec.x - minVec.x,
            y: maxVec.y - minVec.y,
            z: maxVec.z - minVec.z
        )
        
        let center = SCNVector3(
            x: minVec.x + bound.x / 2,
            y: minVec.y + bound.y / 2,
            z: minVec.z + bound.z / 2
        )
        
        targetNode.position = SCNVector3(-center.x, -center.y, -center.z)
        
        let maxDimension = max(bound.x, bound.y, bound.z)
        let cameraDistance = maxDimension * 2.0
        
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(center.x, center.y, center.z + cameraDistance)
        sceneView.scene?.rootNode.addChildNode(cameraNode)
        sceneView.pointOfView = cameraNode
    }
    
    // MARK: - Export Functionality
    func exportDataAsZip(to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // 1. Create temp directory
        let exportFolderURL = documentsURL.appendingPathComponent("ScanExport_\(UUID().uuidString)")
        
        do {
            try fileManager.createDirectory(at: exportFolderURL, withIntermediateDirectories: true)
            
            // 2. Save model
            let modelURL = exportFolderURL.appendingPathComponent("model.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(capturedMeshes)
            try data.write(to: modelURL, options: [.atomicWrite, .completeFileProtection])
            os_log("✅ Saved model JSON at: %@", log: .default, type: .info, modelURL.path)
            
            // 3. Copy images folder (now they won't be deleted prematurely)
            let imagesFolderURL = documentsURL.appendingPathComponent("ScanCapture")
            if fileManager.fileExists(atPath: imagesFolderURL.path) {
                let destinationImagesURL = exportFolderURL.appendingPathComponent("images")
                try fileManager.copyItem(at: imagesFolderURL, to: destinationImagesURL)
                os_log("✅ Copied images to: %@", log: .default, type: .info, destinationImagesURL.path)
            } else {
                os_log("⚠️ No images found at: %@", log: .default, type: .info, imagesFolderURL.path)
            }
            
            // 4. Create ZIP
            try fileManager.zipItem(at: exportFolderURL, to: destinationURL)
            os_log("✅ Created ZIP at: %@", log: .default, type: .info, destinationURL.path)
            
            // 5. Clean up TEMP export folder (but keep original images)
            try fileManager.removeItem(at: exportFolderURL)
            os_log("✅ Cleaned up temp export folder: %@", log: .default, type: .info, exportFolderURL.path)
            
        } catch {
            // Clean up temp folder if something failed
            try? fileManager.removeItem(at: exportFolderURL)
            os_log("❌ Failed to create ZIP: %@", log: .default, type: .error, error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - Actions
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}
