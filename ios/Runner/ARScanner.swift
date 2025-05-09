import ARKit
import SceneKit
import Foundation
import os.log

@available(iOS 13.4, *)
protocol ARScannerDelegate: AnyObject {
    func arScanner(_ scanner: ARScanner, didUpdateStatus status: String)
    func arScanner(_ scanner: ARScanner, didUpdateMeshesCount count: Int)
    func arScannerDidStopScanning(_ scanner: ARScanner)
    func arScanner(_ scanner: ARScanner, showAlertWithTitle title: String, message: String)
    func arScanner(_ scanner: ARScanner, didCaptureDebugImage image: UIImage)
}

@available(iOS 13.4, *)
class ARScanner: NSObject {
    weak var delegate: ARScannerDelegate?
    private let arView = ARSCNView()
    private var allCapturedMeshes = [UUID: CapturedMesh]()
    private var meshNodes = [UUID: SCNNode]()
    private let meshProcessingQueue = DispatchQueue(label: "mesh.processing.queue", qos: .userInitiated)
    private let captureManager = ScanCaptureManager()
    private var lastMessageTime: Date = .distantPast
    private var lastMessage: String?
    private var lastSignificantMeshUpdate = Date()
    private var sceneBounds = BoundingBox()
    private var cameraPositions: [simd_float3] = []
    private var lastCameraPosition: simd_float3?
    
    var view: ARSCNView { return arView }
    var isScanning: Bool = false
    
    // MARK: - Bounding Box for Scene Coverage
    struct BoundingBox {
        var min: simd_float3 = .init(repeating: Float.greatestFiniteMagnitude)
        var max: simd_float3 = .init(repeating: -Float.greatestFiniteMagnitude)
        
        var size: simd_float3 { max - min }
        var volume: Float { abs(size.x * size.y * size.z) }
        var center: simd_float3 { (min + max) / 2 }
        
        mutating func update(with point: simd_float3) {
            min = simd_min(min, point)
            max = simd_max(max, point)
        }
    }
    
    override init() {
        super.init()
        arView.delegate = self
        arView.session.delegate = self
        arView.automaticallyUpdatesLighting = true
        arView.antialiasingMode = .multisampling4X
        captureManager.delegate = self
        setupThermalStateObserver()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func startScan() {
        guard !isScanning else { return }
        
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            delegate?.arScanner(self, showAlertWithTitle: "Device Not Supported",
                              message: "This device needs LiDAR for scanning. Try a newer iPhone or iPad with LiDAR.")
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
        updateStatus("Ready to scan! Move your device slowly to capture the scene.", isCritical: true)
    }
    
    func stopScan() {
        guard isScanning else { return }
        arView.session.pause()
        isScanning = false
        delegate?.arScannerDidStopScanning(self)
        updateStatus("Scan paused. You can resume or export your work.", isCritical: true)
    }
    
    func restartScan() {
        stopScan()
        allCapturedMeshes.removeAll()
        meshNodes.values.forEach { $0.removeFromParentNode() }
        meshNodes.removeAll()
        captureManager.cleanupCaptureDirectory()
        sceneBounds = BoundingBox()
        cameraPositions.removeAll()
        lastCameraPosition = nil
        lastSignificantMeshUpdate = Date()
        updateStatus("Restarting scan! Clearing previous data...", isCritical: true)
        startScan()
    }
    
    func getCapturedMeshes() -> [CapturedMesh] {
        return Array(allCapturedMeshes.values)
    }
    
    private func process(_ meshAnchor: ARMeshAnchor) {
        let geometry = meshAnchor.geometry
        let transform = meshAnchor.transform
        
        // Update scene bounds
        updateSceneBounds(with: geometry.vertices)
        
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
                self.updateStatus("Oops, couldn't process this mesh. Keep scanning or try restarting.", isCritical: true)
            }
        }
        
        meshProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let vertices = try self.extractVertices(from: geometry.vertices)
                let normals = try self.extractNormals(from: geometry.normals)
                let indices = try self.extractIndices(from: geometry.faces)
                
                let mesh = CapturedMesh(
                    vertices: vertices,
                    normals: normals,
                    indices: indices,
                    transform: transform
                )
                
                DispatchQueue.main.async {
                    self.allCapturedMeshes[meshAnchor.identifier] = mesh
                    self.lastSignificantMeshUpdate = Date()
                    let count = self.allCapturedMeshes.count
                    self.delegate?.arScanner(self, didUpdateMeshesCount: count)
                    self.provideProgressFeedback(count: count)
                }
            } catch {
                self.updateStatus("Oops, couldn't extract mesh data. Keep scanning or try restarting.", isCritical: true)
            }
        }
    }
    
    private func updateSceneBounds(with vertices: ARGeometrySource) {
        for i in 0..<vertices.count {
            do {
                let vertex = try vertices.safeVertex(at: UInt32(i))
                sceneBounds.update(with: vertex)
            } catch {
                os_log("Failed to update scene bounds for vertex %d", log: OSLog.default, type: .error, i)
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
    
    // MARK: - Enhanced Status Messaging
    
    private func shouldUpdateMessage(_ message: String, isCritical: Bool) -> Bool {
        guard !isCritical else { return true }
        
        let now = Date()
        let timeSinceLast = now.timeIntervalSince(lastMessageTime)
        
        // Skip Levenshtein for empty or identical messages
        if message.isEmpty || lastMessage == nil || message == lastMessage {
            return false
        }
        
        let isSimilar = message.levenshteinDistance(to: lastMessage!) < 0.7
        
        if timeSinceLast >= 5.0 && !isSimilar {
            lastMessageTime = now
            lastMessage = message
            return true
        }
        return false
    }
    
    private func updateStatus(_ message: String, isCritical: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.shouldUpdateMessage(message, isCritical: isCritical) {
                self.delegate?.arScanner(self, didUpdateStatus: message)
                os_log("Status update: %@", log: OSLog.default, type: .info, message)
            }
        }
    }
    
    private func provideProgressFeedback(count: Int) {
        let coverage = estimateSceneCoverage()
        let completionPercentage = Int(coverage * 100)
        let progressMessages = [
            (25, "Nice start! Keep exploring the area."),
            (50, "You're halfway done! Look for missed areas."),
            (75, "Almost there! Check edges and corners."),
            (100, "Scan complete! Review for any missed spots.")
        ]
        
        if let message = progressMessages.first(where: { $0.0 == completionPercentage })?.1 {
            updateStatus(message, isCritical: true)
        }
    }
    
    private func analyzeSurfaceFeatures(frame: ARFrame) {
        let featureCount = frame.rawFeaturePoints?.points.count ?? 0
        if featureCount < 150 {
            updateStatus("Low surface detail detected. Scan textured areas for better results.", isCritical: false)
        } else if featureCount > 1000 {
            updateStatus("Great surface detail! Maintain this distance from objects.", isCritical: false)
        }
    }
    
    private func provideScanningGuidance(frame: ARFrame) {
        let cameraPos = frame.camera.transform.columns.3.xyz
        
        // Track camera movement
        cameraPositions.append(cameraPos)
        if cameraPositions.count > 60 { cameraPositions.removeFirst() }
        
        if isMakingCircularMotion() {
            updateStatus("Good circular pattern! Now try vertical movements to cover height.", isCritical: false)
        }
        
        if isRepeatingPath(cameraPos: cameraPos) {
            updateStatus("You're covering the same area. Try expanding outward to new sections.", isCritical: false)
        }
    }
    
    private func provideTemporalGuidance() {
        let timeSinceLastMesh = Date().timeIntervalSince(lastSignificantMeshUpdate)
        if timeSinceLastMesh > 8.0 {
            updateStatus("No new details captured recently. Try moving to a new area.", isCritical: false)
        }
    }
    
    private func provideAngleGuidance(frame: ARFrame) {
        let cameraTiltAngle = calculateCameraTilt(frame.camera.transform)
        if cameraTiltAngle > 45 {
            updateStatus("Tilt device downward to capture lower surfaces.", isCritical: false)
        } else if cameraTiltAngle < -30 {
            updateStatus("Angle device upward to capture higher areas.", isCritical: false)
        }
    }
    
    private func provideCoverageFeedback() {
        let coverage = estimateSceneCoverage()
        if coverage > 0.75 {
            updateStatus("Almost complete! Check for missed spots near the edges.", isCritical: false)
        } else if coverage < 0.3 {
            updateStatus("Keep exploring! We've only covered a small portion so far.", isCritical: false)
        }
    }
    
    private func estimateSceneCoverage() -> Float {
        guard sceneBounds.volume > 0 else { return 0.0 }
        
        // Simplified convex hull volume approximation
        let coveredPoints = Float(allCapturedMeshes.count * 1000) // Approximate points per mesh
        let totalVolume = sceneBounds.volume
        let estimatedCoverage = Swift.min(1.0, coveredPoints / (totalVolume * 1000.0))
        return estimatedCoverage
    }
    
    private func calculateCameraTilt(_ transform: simd_float4x4) -> Float {
        let upVector = simd_float3(0, 1, 0)
        let cameraForward = simd_float3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        let angle = atan2(cameraForward.y, sqrt(cameraForward.x * cameraForward.x + cameraForward.z * cameraForward.z))
        return angle * 180.0 / .pi // Convert radians to degrees
    }
    
    private func isMakingCircularMotion() -> Bool {
        guard cameraPositions.count >= 20 else { return false }
        
        // Analyze last 20 positions for circular pattern
        let recentPositions = cameraPositions.suffix(20)
        let center = recentPositions.reduce(simd_float3.zero) { $0 + $1 } / Float(recentPositions.count)
        let distances = recentPositions.map { simd_distance($0, center) }
        let avgDistance = distances.reduce(0, +) / Float(distances.count)
        let variance = distances.map { pow($0 - avgDistance, 2) }.reduce(0, +) / Float(distances.count)
        
        return variance < 0.1 // Low variance indicates circular motion
    }
    
    private func isRepeatingPath(cameraPos: simd_float3) -> Bool {
        guard let lastPos = lastCameraPosition else {
            lastCameraPosition = cameraPos
            return false
        }
        
        let distance = simd_distance(cameraPos, lastPos)
        lastCameraPosition = cameraPos
        
        // Check if camera is lingering in same area
        let recentPositions = cameraPositions.suffix(10)
        let avgPosition = recentPositions.reduce(simd_float3.zero) { $0 + $1 } / Float(recentPositions.count)
        let maxDistance = recentPositions.map { simd_distance($0, avgPosition) }.max() ?? 0
        
        return distance < 0.1 && maxDistance < 0.2 // Small movements in confined area
    }
    
    private func setupThermalStateObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }
    
    @objc private func thermalStateChanged(_ notification: Notification) {
        if ProcessInfo.processInfo.thermalState == .critical {
            updateStatus("Your device is getting warm. Take a quick break to cool it down.", isCritical: true)
        }
    }
}

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
        
        // Check light conditions
        if let lightEstimate = frame.lightEstimate?.ambientIntensity, lightEstimate < 100 {
            updateStatus("It's a bit dark here. Try adding more light for better results.", isCritical: false)
            return
        }
        
        // Check world mapping status
        switch frame.worldMappingStatus {
        case .notAvailable:
            updateStatus("Start exploring! Move your device slowly to map the area.", isCritical: false)
        case .limited:
            updateStatus("Keep moving slowly to help me understand the space.", isCritical: false)
        case .extending:
            updateStatus("Nice work! The map is coming together, keep going.", isCritical: false)
        case .mapped:
            updateStatus("Great job! The area is mapped, keep scanning for details.", isCritical: false)
        @unknown default:
            updateStatus("Something's off. Try moving slowly or restarting the scan.", isCritical: false)
        }
        
        // Check camera tracking state
        switch frame.camera.trackingState {
        case .normal:
            break // Use world mapping status and enhanced feedback
        case .notAvailable:
            updateStatus("Hmm, I can't track right now. Try restarting the scan.", isCritical: false)
        case .limited(.excessiveMotion):
            updateStatus("Whoa, you're moving too fast! Slow down to capture details clearly.", isCritical: false)
        case .limited(.insufficientFeatures):
            updateStatus("This spot's a bit plain. Try aiming at textured surfaces.", isCritical: false)
        case .limited(.initializing):
            updateStatus("Just warming up! Move slowly to help me get started.", isCritical: false)
        case .limited(.relocalizing):
            updateStatus("Lost my place! Try moving back to where you started.", isCritical: false)
        case .limited(_):
            updateStatus("Something's off. Try moving slowly or restarting the scan.", isCritical: false)
        @unknown default:
            updateStatus("Something's off. Try moving slowly or restarting the scan.", isCritical: false)
        }
        
        // Enhanced feedback
        analyzeSurfaceFeatures(frame: frame)
        provideScanningGuidance(frame: frame)
        provideTemporalGuidance()
        provideAngleGuidance(frame: frame)
        provideCoverageFeedback()
    }
}

@available(iOS 13.4, *)
extension ARScanner: ScanCaptureManagerDelegate {
    func scanCaptureManagerReachedStorageLimit(_ manager: ScanCaptureManager) {
        DispatchQueue.main.async {
            self.stopScan()
            self.delegate?.arScanner(self, showAlertWithTitle: "Storage Full",
                                   message: "Storage is full! Export your scan to free up space.")
        }
    }
    
    func scanCaptureManager(_ manager: ScanCaptureManager, didUpdateStatus status: String) {
        updateStatus(status, isCritical: false)
    }
}

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

extension String {
    func levenshteinDistance(to other: String) -> Double {
        // Handle empty string cases
        if self.isEmpty && other.isEmpty {
            return 0.0
        }
        if self.isEmpty || other.isEmpty {
            return 1.0
        }
        
        let m = self.count
        let n = other.count
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m {
            matrix[i][0] = i
        }
        for j in 0...n {
            matrix[0][j] = j
        }
        
        for i in 1...m {
            for j in 1...n {
                let cost = self[self.index(self.startIndex, offsetBy: i - 1)] == other[other.index(other.startIndex, offsetBy: j - 1)] ? 0 : 1
                matrix[i][j] = Swift.min(
                    matrix[i-1][j] + 1,     // deletion
                    matrix[i][j-1] + 1,     // insertion
                    matrix[i-1][j-1] + cost // substitution
                )
            }
        }
        
        return Double(matrix[m][n]) / Double(max(m, n))
    }
}

extension ARCamera.TrackingState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .normal:
            return "Normal"
        case .notAvailable:
            return "Not Available"
        case .limited(let reason):
            switch reason {
            case .excessiveMotion:
                return "Limited - Excessive Motion"
            case .insufficientFeatures:
                return "Limited - Insufficient Features"
            case .initializing:
                return "Limited - Initializing"
            case .relocalizing:
                return "Limited - Relocalizing"
            @unknown default:
                return "Limited - Unknown Reason"
            }
        }
    }
}
