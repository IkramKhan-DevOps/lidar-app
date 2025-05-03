import ARKit
import SceneKit

@available(iOS 13.4, *)
protocol ARScannerDelegate: AnyObject {
    func arScanner(_ scanner: ARScanner, didUpdateStatus status: String)
    func arScanner(_ scanner: ARScanner, didUpdateMeshesCount count: Int)
    func arScannerDidStopScanning(_ scanner: ARScanner)
    func arScanner(_ scanner: ARScanner, showAlertWithTitle title: String, message: String)
}

@available(iOS 13.4, *)
class ARScanner: NSObject {
    weak var delegate: ARScannerDelegate?
    private let arView = ARSCNView()
    private var allCapturedMeshes = [UUID: CapturedMesh]()
    private var meshNodes = [UUID: SCNNode]()
    private let meshProcessingQueue = DispatchQueue(label: "mesh.processing.queue", qos: .userInitiated)

    // Capture images and camera transforms
    private let captureManager = ScanCaptureManager()
    
    var view: ARSCNView { return arView }
    var isScanning: Bool = false
    
    override init() {
        super.init()
        arView.delegate = self
        arView.session.delegate = self
        arView.automaticallyUpdatesLighting = true
        arView.antialiasingMode = .multisampling4X
    }
    
    func startScan() {
        guard !isScanning else { return }
        
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            delegate?.arScanner(self, showAlertWithTitle: "Unsupported Device",
                              message: "Scene reconstruction requires a device with LiDAR or equivalent capabilities.")
            return
        }
        
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .mesh
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        if #available(iOS 14.0, *) {
            config.frameSemantics = [.smoothedSceneDepth, .sceneDepth]
        }
        
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isScanning = true
        delegate?.arScanner(self, didUpdateStatus: "Scanning... Move slowly")
    }
    
    func stopScan() {
        guard isScanning else { return }
        arView.session.pause()
        isScanning = false
        delegate?.arScannerDidStopScanning(self)
        delegate?.arScanner(self, didUpdateStatus: "Scan stopped")
    }
    
    func restartScan() {
        stopScan()
        allCapturedMeshes.removeAll()
        meshNodes.values.forEach { $0.removeFromParentNode() }
        meshNodes.removeAll()
        startScan()
    }
    
    func getCapturedMeshes() -> [CapturedMesh] {
        return Array(allCapturedMeshes.values)
    }
    
    // MARK: - Mesh Processing
    private func process(_ meshAnchor: ARMeshAnchor) {
        let geometry = meshAnchor.geometry
        let transform = meshAnchor.transform
        
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
        
        meshProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let vertices = try self.extractVertices(from: geometry.vertices)
                let normals = try self.extractNormals(from: geometry.normals) // Fixed: Removed force unwrap
                let indices = try self.extractIndices(from: geometry.faces)
                
                let mesh = CapturedMesh(
                    vertices: vertices,
                    normals: normals,
                    indices: indices,
                    transform: transform
                )
                
                DispatchQueue.main.async {
                    self.allCapturedMeshes[meshAnchor.identifier] = mesh
                    self.delegate?.arScanner(self, didUpdateMeshesCount: self.allCapturedMeshes.count)
                    self.delegate?.arScanner(self, didUpdateStatus: "Scanning... (\(self.allCapturedMeshes.count) meshes captured)")
                }
            } catch {
                print("Mesh processing error: \(error)")
            }
        }
    }

    private func extractNormals(from source: ARGeometrySource) throws -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>]()
        normals.reserveCapacity(source.count)
        
        for i in 0..<source.count {
            let normal = try source.safeVertex(at: UInt32(i))
            normals.append(normal)
        }
        
        return normals
    }
    
    private func createPolycamStyleNode(from meshAnchor: ARMeshAnchor) throws -> SCNNode {
        let node = SCNNode()
        
        let solidGeo = try createSolidGeometry(from: meshAnchor)
        solidGeo.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.08)
        node.addChildNode(SCNNode(geometry: solidGeo))
        
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
        
        var vertexArray = [SCNVector3]()
        for i in 0..<vertices.count {
            let vertex = try vertices.safeVertex(at: UInt32(i))
            vertexArray.append(SCNVector3(vertex))
        }
        
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
        
        var vertexArray = [SCNVector3]()
        for i in 0..<vertices.count {
            let vertex = try vertices.safeVertex(at: UInt32(i))
            vertexArray.append(SCNVector3(vertex))
        }
        
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
}

// MARK: - Safe Buffer Access Extensions
@available(iOS 13.4, *)
struct GeometrySourceError: Error {
    let message: String
}

@available(iOS 13.4, *)
extension ARGeometrySource {
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

// MARK: - ARSessionDelegate, ARSCNViewDelegate
@available(iOS 13.4, *)
extension ARScanner: ARSessionDelegate, ARSCNViewDelegate {
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                process(meshAnchor)
            }
        }
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        captureManager.tryCapture(frame: frame)
        
        DispatchQueue.main.async {
            switch frame.worldMappingStatus {
            case .notAvailable:
                self.delegate?.arScanner(self, didUpdateStatus: "Move slowly to initialize tracking")
            case .limited:
                self.delegate?.arScanner(self, didUpdateStatus: "Limited tracking - move slowly, ensure features")
            case .extending:
                self.delegate?.arScanner(self, didUpdateStatus: "Extending map - good progress")
            case .mapped:
                self.delegate?.arScanner(self, didUpdateStatus: "Environment mapped - continue scanning")
            @unknown default:
                self.delegate?.arScanner(self, didUpdateStatus: "Unknown mapping status")
            }

            switch frame.camera.trackingState {
            case .normal:
                break
            case .notAvailable:
                self.delegate?.arScanner(self, didUpdateStatus: "Tracking not available - check device")
            case .limited(.excessiveMotion):
                self.delegate?.arScanner(self, didUpdateStatus: "Slow down - moving too fast")
            case .limited(.insufficientFeatures):
                self.delegate?.arScanner(self, didUpdateStatus: "Add more features - too plain")
            case .limited(.initializing):
                self.delegate?.arScanner(self, didUpdateStatus: "Initializing - move slowly")
            case .limited(.relocalizing):
                self.delegate?.arScanner(self, didUpdateStatus: "Relocalizing - return to start")
            case .limited(_):
                self.delegate?.arScanner(self, didUpdateStatus: "Tracking limited - check environment")
            @unknown default:
                self.delegate?.arScanner(self, didUpdateStatus: "Unknown tracking issue")
            }
        }
    }
}
