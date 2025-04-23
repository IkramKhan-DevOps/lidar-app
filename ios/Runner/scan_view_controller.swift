import UIKit
import ARKit
import SceneKit
import AVFoundation

// MARK: - Data Model
struct CapturedMesh: Codable {
    var vertices: [SIMD3<Float>]
    var indices: [UInt32]
    var transform: [[Float]]  // Serialized version of simd_float4x4
    
    init(vertices: [SIMD3<Float>], indices: [UInt32], transform: simd_float4x4) {
        self.vertices = vertices
        self.indices = indices
        self.transform = transform.toArray()
    }
    
    func getTransform() -> simd_float4x4 {
        return simd_float4x4(self.transform)
    }
}

extension simd_float4x4 {
    func toArray() -> [[Float]] {
        return [
            [columns.0.x, columns.0.y, columns.0.z, columns.0.w],
            [columns.1.x, columns.1.y, columns.1.z, columns.1.w],
            [columns.2.x, columns.2.y, columns.2.z, columns.2.w],
            [columns.3.x, columns.3.y, columns.3.z, columns.3.w]
        ]
    }
    
    init(_ array: [[Float]]) {
        self.init(
            SIMD4<Float>(array[0][0], array[0][1], array[0][2], array[0][3]),
            SIMD4<Float>(array[1][0], array[1][1], array[1][2], array[1][3]),
            SIMD4<Float>(array[2][0], array[2][1], array[2][2], array[2][3]),
            SIMD4<Float>(array[3][0], array[3][1], array[3][2], array[3][3])
        )
    }
}

@available(iOS 13.4, *)
class ScanViewController: UIViewController, ARSessionDelegate, ARSCNViewDelegate {
    
    // MARK: - Properties
    var arView: ARSCNView!
    private var allCapturedMeshes = [CapturedMesh]()
    private var meshNodes = [UUID: SCNNode]()
    private var notificationView: UIView?
    private let meshProcessingQueue = DispatchQueue(label: "mesh.processing.queue", qos: .userInitiated)
    private let fileManager = FileManager.default
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupARView()
        startScan()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arView.session.pause()
    }
    
    // MARK: - AR Configuration
    func setupARView() {
        arView = ARSCNView(frame: view.bounds)
        view.addSubview(arView)
        arView.delegate = self
        arView.session.delegate = self
        arView.automaticallyUpdatesLighting = true
        arView.antialiasingMode = .multisampling4X
    }
    
    func startScan() {
        checkCameraPermission { [weak self] granted in
            guard let self = self else { return }
            
            guard granted else {
                self.showAlert(title: "Permission Denied", message: "Camera access is required for AR scanning.")
                return
            }
            
            guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
                self.showAlert(title: "Unsupported Device", message: "Scene reconstruction requires a device with LiDAR or equivalent capabilities.")
                return
            }
            
            let config = ARWorldTrackingConfiguration()
            config.sceneReconstruction = .mesh
            config.planeDetection = [.horizontal, .vertical]
            config.environmentTexturing = .automatic
            
            self.arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }
    }
    
    // MARK: - Data Persistence
    func saveCapturedMeshes() throws -> URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent("scan_\(Date().timeIntervalSince1970).json")
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(allCapturedMeshes)
        try data.write(to: fileURL)
        
        return fileURL
    }
    
    func loadCapturedMeshes(from url: URL) throws -> [CapturedMesh] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([CapturedMesh].self, from: data)
    }
    
    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let meshAnchor = anchor as? ARMeshAnchor else { continue }
            process(meshAnchor)
        }
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        switch frame.worldMappingStatus {
        case .notAvailable, .limited:
            showNotification(message: "Move your device slowly to map the environment.")
        case .extending, .mapped:
            break
        @unknown default:
            break
        }
        
        if frame.camera.trackingState != .normal {
            showNotification(message: "Ensure good lighting and slow movement for better tracking.")
        }
    }
    
    // MARK: - Mesh Processing
    private func process(_ meshAnchor: ARMeshAnchor) {
        let geometry = meshAnchor.geometry
        let transform = meshAnchor.transform
        
        // Update visualization first for responsiveness
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
                print("Error creating mesh node: \(error)")
            }
        }
        
        // Process data in background
        meshProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let vertices = try self.extractVertices(from: geometry.vertices)
                let indices = try self.extractIndices(from: geometry.faces)
                
                let mesh = CapturedMesh(
                    vertices: vertices,
                    indices: indices,
                    transform: transform
                )
                
                DispatchQueue.main.async {
                    self.allCapturedMeshes.append(mesh)
                    print("Captured mesh with \(vertices.count) vertices and \(indices.count/3) faces")
                }
            } catch {
                print("Mesh processing error: \(error)")
            }
        }
    }
    
    // MARK: - Mesh Visualization
    private func createPolycamStyleNode(from meshAnchor: ARMeshAnchor) throws -> SCNNode {
        let node = SCNNode()
        
        // 1. Solid base (transparent)
        let solidGeo = try createSolidGeometry(from: meshAnchor)
        solidGeo.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.08)
        node.addChildNode(SCNNode(geometry: solidGeo))
        
        // 2. Wireframe overlay
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
        
        // Convert vertices with proper alignment
        var vertexArray = [SCNVector3]()
        for i in 0..<vertices.count {
            let vertex = try vertices.safeVertex(at: UInt32(i))
            vertexArray.append(SCNVector3(vertex))
        }
        
        // Convert faces
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
        
        // Convert vertices with proper alignment
        var vertexArray = [SCNVector3]()
        for i in 0..<vertices.count {
            let vertex = try vertices.safeVertex(at: UInt32(i))
            vertexArray.append(SCNVector3(vertex))
        }
        
        // Create line indices for all edges
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
    
    // MARK: - Data Extraction
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
    
    // MARK: - Utilities
    private func checkCameraPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
    }
    
    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }
    
    private func showNotification(message: String) {
        DispatchQueue.main.async {
            // Remove any existing notification
            self.notificationView?.removeFromSuperview()
            
            // Create notification view
            let notificationView = UIView()
            notificationView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
            notificationView.layer.cornerRadius = 8
            notificationView.clipsToBounds = true
            
            // Create label
            let label = UILabel()
            label.text = message
            label.textColor = .white
            label.font = .systemFont(ofSize: 16)
            label.numberOfLines = 0
            label.textAlignment = .center
            notificationView.addSubview(label)
            
            // Layout label
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: notificationView.topAnchor, constant: 8),
                label.bottomAnchor.constraint(equalTo: notificationView.bottomAnchor, constant: -8),
                label.leadingAnchor.constraint(equalTo: notificationView.leadingAnchor, constant: 16),
                label.trailingAnchor.constraint(equalTo: notificationView.trailingAnchor, constant: -16)
            ])
            
            // Add to view
            self.arView.addSubview(notificationView)
            self.notificationView = notificationView
            
            // Layout notification view
            notificationView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                notificationView.leadingAnchor.constraint(equalTo: self.arView.leadingAnchor, constant: 16),
                notificationView.trailingAnchor.constraint(equalTo: self.arView.trailingAnchor, constant: -16),
                notificationView.bottomAnchor.constraint(equalTo: self.arView.safeAreaLayoutGuide.bottomAnchor, constant: -16)
            ])
            
            // Animate in
            notificationView.transform = CGAffineTransform(translationX: 0, y: 100)
            notificationView.alpha = 0
            UIView.animate(withDuration: 0.3, animations: {
                notificationView.transform = .identity
                notificationView.alpha = 1
            }) { _ in
                // Auto-dismiss after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    UIView.animate(withDuration: 0.3, animations: {
                        notificationView.transform = CGAffineTransform(translationX: 0, y: 100)
                        notificationView.alpha = 0
                    }) { _ in
                        notificationView.removeFromSuperview()
                        if self.notificationView == notificationView {
                            self.notificationView = nil
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Safe Buffer Access Extensions
@available(iOS 13.4, *)
extension ARGeometrySource {
    struct GeometrySourceError: Error {
        let message: String
    }
    
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
