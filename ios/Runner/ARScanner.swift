import ARKit
import SceneKit
import Foundation
import os.log
import UIKit
import AVFoundation
import SSZipArchive
import Vision
import CoreLocation
import simd
import QuickLook

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
        updateStatus("Scan paused. Preparing model view...", isCritical: true)
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
    
    private func shouldUpdateMessage(_ message: String, isCritical: Bool) -> Bool {
        guard !isCritical else { return true }
        
        let now = Date()
        let timeSinceLast = now.timeIntervalSince(lastMessageTime)
        
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
        
        let coveredPoints = Float(allCapturedMeshes.count * 1000)
        let totalVolume = sceneBounds.volume
        let estimatedCoverage = Swift.min(1.0, coveredPoints / (totalVolume * 1000.0))
        return estimatedCoverage
    }
    
    private func calculateCameraTilt(_ transform: simd_float4x4) -> Float {
        let upVector = simd_float3(0, 1, 0)
        let cameraForward = simd_float3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        let angle = atan2(cameraForward.y, sqrt(cameraForward.x * cameraForward.x + cameraForward.z * cameraForward.z))
        return angle * 180.0 / .pi
    }
    
    private func isMakingCircularMotion() -> Bool {
        guard cameraPositions.count >= 20 else { return false }
        
        let recentPositions = cameraPositions.suffix(20)
        let center = recentPositions.reduce(simd_float3.zero) { $0 + $1 } / Float(recentPositions.count)
        let distances = recentPositions.map { simd_distance($0, center) }
        let avgDistance = distances.reduce(0, +) / Float(distances.count)
        let variance = distances.map { pow($0 - avgDistance, 2) }.reduce(0, +) / Float(distances.count)
        
        return variance < 0.1
    }
    
    private func isRepeatingPath(cameraPos: simd_float3) -> Bool {
        guard let lastPos = lastCameraPosition else {
            lastCameraPosition = cameraPos
            return false
        }
        
        let distance = simd_distance(cameraPos, lastPos)
        lastCameraPosition = cameraPos
        
        let recentPositions = cameraPositions.suffix(10)
        let avgPosition = recentPositions.reduce(simd_float3.zero) { $0 + $1 } / Float(recentPositions.count)
        let maxDistance = recentPositions.map { simd_distance($0, avgPosition) }.max() ?? 0
        
        return distance < 0.1 && maxDistance < 0.2
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
        
        if let lightEstimate = frame.lightEstimate?.ambientIntensity, lightEstimate < 100 {
            updateStatus("It's a bit dark here. Try adding more light for better results.", isCritical: false)
            return
        }
        
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
        
        switch frame.camera.trackingState {
        case .normal:
            break
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
                                   message: "Storage is full! Clear some space or process your scan.")
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
                    matrix[i-1][j] + 1,
                    matrix[i][j-1] + 1,
                    matrix[i-1][j-1] + cost
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

@available(iOS 13.4, *)
class ScanViewController: UIViewController {
    private let arScanner = ARScanner()
    let captureManager = ScanCaptureManager()
    private let controlPanel = ControlPanel()
    
    private var activityIndicator: UIActivityIndicatorView?
    private var isPresentingPreview: Bool = false
    
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
    
    private func cleanupTemporaryFiles() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.captureManager.cleanupCaptureDirectory()
            os_log("Cleaned up temporary capture files", log: OSLog.default, type: .info)
        }
    }
    
    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }
    
    private func showModelView() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isPresentingPreview = true
            let previewVC = ModelViewController()
            previewVC.capturedMeshes = self.arScanner.getCapturedMeshes()
            previewVC.modalPresentationStyle = .fullScreen
            self.present(previewVC, animated: true)
        }
    }
}

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
            if !scanner.getCapturedMeshes().isEmpty {
                self.showModelView()
            }
        }
    }
    
    func arScanner(_ scanner: ARScanner, showAlertWithTitle title: String, message: String) {
        showAlert(title: title, message: message)
    }
    
    func arScanner(_ scanner: ARScanner, didCaptureDebugImage image: UIImage) {
    }
}

@available(iOS 13.4, *)
extension ScanViewController: ScanCaptureManagerDelegate {
    func scanCaptureManagerReachedStorageLimit(_ manager: ScanCaptureManager) {
        DispatchQueue.main.async {
            self.arScanner.stopScan()
            self.showAlert(
                title: "Storage Full",
                message: "Storage is full! Clear some space or process your scan."
            )
        }
    }
    
    func scanCaptureManager(_ manager: ScanCaptureManager, didUpdateStatus status: String) {
        DispatchQueue.main.async {
            self.controlPanel.updateStatus(status)
        }
    }
}

@available(iOS 13.4, *)
extension ScanViewController: ControlPanelDelegate {
    func controlPanelDidTapToggleScan(_ panel: ControlPanel) {
        if arScanner.isScanning {
            arScanner.stopScan()
        } else {
            arScanner.startScan()
        }
    }
    
    func controlPanelDidTapRestart(_ panel: ControlPanel) {
        arScanner.restartScan()
        cleanupTemporaryFiles()
    }
}

protocol ScanCaptureManagerDelegate: AnyObject {
    func scanCaptureManagerReachedStorageLimit(_ manager: ScanCaptureManager)
    func scanCaptureManager(_ manager: ScanCaptureManager, didUpdateStatus status: String)
}

class ScanCaptureManager {
    private let fileManager = FileManager.default
    private let captureFolderURL: URL
    private var imageIndex: Int = 0
    private var optimalFrameInterval: Int = 10
    private let minMovementDistance: Float = 0.05
    private var lastCameraPosition: SIMD3<Float>?
    private var lastQualityScore: Float = 0.5
    private var lastCaptureTime: TimeInterval = 0
    
    private let logger = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "com.your.app",
        category: "ScanCapture"
    )
    
    private let maxStorageMB: Int = 500
    private var currentStorageSize: Int64 = 0
    
    weak var delegate: ScanCaptureManagerDelegate?

    init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        captureFolderURL = docs.appendingPathComponent("ScanCapture")
        cleanupCaptureDirectory()
        createCaptureDirectory()
    }

    func tryCapture(frame: ARFrame) {
        guard shouldCapture(frame: frame) else { return }
        
        if let processedImage = preprocessImage(frame.capturedImage) {
            saveProcessedImage(processedImage, frame: frame)
            saveCameraTransform(transform: frame.camera.transform, frame: frame)
            imageIndex += 1
            
            if imageIndex % 10 == 0 {
                ensureStorageLimit()
            }
        }
    }

    private func shouldCapture(frame: ARFrame) -> Bool {
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastCaptureTime > Double(optimalFrameInterval)/30.0 else {
            return false
        }
        
        let currentPosition = frame.camera.transform.columns.3.xyz
        if let lastPosition = lastCameraPosition {
            let distance = simd_distance(currentPosition, lastPosition)
            guard distance >= minMovementDistance else {
                delegate?.scanCaptureManager(self, didUpdateStatus: "Skipping - insufficient movement")
                return false
            }
        }
        
        let avgBrightness = frame.lightEstimate?.ambientIntensity ?? 1000
        guard (300...2000).contains(avgBrightness) else {
            delegate?.scanCaptureManager(self, didUpdateStatus: "Skipping - poor lighting")
            return false
        }
        
        if let motion = frame.camera.trackingState.motionBlurEstimate, motion > 0.1 {
            delegate?.scanCaptureManager(self, didUpdateStatus: "Skipping - motion blur detected")
            return false
        }
        
        let qualityScore = calculateQualityScore(frame: frame)
        adjustCaptureRate(qualityScore: qualityScore)
        
        lastCameraPosition = currentPosition
        lastCaptureTime = currentTime
        return true
    }
    
    private func calculateQualityScore(frame: ARFrame) -> Float {
        var score: Float = 0
        
        switch frame.camera.trackingState {
        case .normal: score += 0.4
        case .limited: score += 0.2
        default: score += 0
        }
        
        if let rawFeaturePoints = frame.rawFeaturePoints {
            let featureDensity = Float(rawFeaturePoints.points.count) / 1000.0
            score += min(featureDensity, 0.3)
        }
        
        if let lightEstimate = frame.lightEstimate {
            let normalizedLight = Float((lightEstimate.ambientIntensity - 300) / 1700.0)
            score += min(max(normalizedLight, 0), 0.3)
        }
        
        return score
    }
    
    private func adjustCaptureRate(qualityScore: Float) {
        let baseInterval = 10
        let qualityDelta = qualityScore - lastQualityScore
        
        if qualityDelta < -0.2 {
            optimalFrameInterval = max(baseInterval / 2, 5)
            delegate?.scanCaptureManager(self, didUpdateStatus: "Increased capture rate - quality dropped")
        } else if qualityDelta > 0.2 {
            optimalFrameInterval = min(baseInterval * 2, 30)
            delegate?.scanCaptureManager(self, didUpdateStatus: "Decreased capture rate - quality improved")
        }
        
        lastQualityScore = qualityScore
    }

    private func preprocessImage(_ pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        let filters = ciImage.autoAdjustmentFilters(options: [.enhance: true])
        var processedImage = ciImage
        for filter in filters {
            filter.setValue(processedImage, forKey: kCIInputImageKey)
            processedImage = filter.outputImage ?? processedImage
        }
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(processedImage, from: processedImage.extent) else {
            delegate?.scanCaptureManager(self, didUpdateStatus: "Failed to process image")
            return nil
        }
        
        return cgImage
    }
    
    private func saveProcessedImage(_ cgImage: CGImage, frame: ARFrame) {
        let uiImage = UIImage(cgImage: cgImage)
        let imageURL = captureFolderURL.appendingPathComponent("image_\(imageIndex).jpg")
        
        if let jpegData = uiImage.jpegData(compressionQuality: 0.9) {
            do {
                try jpegData.write(to: imageURL)
                currentStorageSize += Int64(jpegData.count)
                
                if imageIndex % 20 == 0 {
                    let debugImage = debugVisualizeFeatures(image: uiImage)
                    let debugURL = captureFolderURL.appendingPathComponent("debug_\(imageIndex).jpg")
                    try debugImage.jpegData(compressionQuality: 0.8)?.write(to: debugURL)
                }
            } catch {
                os_log("Failed to save image: %@", log: logger, type: .error, error.localizedDescription)
            }
        }
    }
    
    private func debugVisualizeFeatures(image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }
        
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(ciImage: ciImage)
        
        UIGraphicsBeginImageContext(image.size)
        image.draw(at: .zero)
        
        do {
            try handler.perform([request])
            if let results = request.results {
                for observation in results {
                    let boundingBox = observation.boundingBox
                    let rect = VNImageRectForNormalizedRect(boundingBox,
                                                          Int(image.size.width),
                                                          Int(image.size.height))
                    let path = UIBezierPath(rect: rect)
                    UIColor.red.setStroke()
                    path.stroke()
                }
            }
        } catch {
            print("Feature detection error: \(error)")
        }
        
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result ?? image
    }

    private func saveCameraTransform(transform: simd_float4x4, frame: ARFrame) {
        let confidence: Float
        switch frame.worldMappingStatus {
        case .mapped: confidence = 1.0
        case .extending: confidence = 0.8
        case .limited: confidence = 0.5
        case .notAvailable: confidence = 0.2
        @unknown default: confidence = 0.5
        }
        
        let poseData: [String: Any] = [
            "transform": transform.toArray(),
            "confidence": confidence,
            "timestamp": CACurrentMediaTime(),
            "light_estimate": frame.lightEstimate?.ambientIntensity ?? 0,
            "tracking_state": frame.camera.trackingState.description,
            "feature_count": frame.rawFeaturePoints?.points.count ?? 0
        ]
        
        let poseURL = captureFolderURL.appendingPathComponent("image_\(imageIndex)_pose.json")
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: poseData, options: [.prettyPrinted])
            try jsonData.write(to: poseURL)
            currentStorageSize += Int64(jsonData.count)
        } catch {
            os_log("Failed to save camera transform: %@", log: logger, type: .error, error.localizedDescription)
        }
    }

    private func createCaptureDirectory() {
        do {
            try fileManager.createDirectory(at: captureFolderURL,
                                         withIntermediateDirectories: true,
                                         attributes: nil)
        } catch {
            os_log("Failed to create capture directory: %@", log: logger, type: .error, error.localizedDescription)
        }
    }

    func cleanupCaptureDirectory() {
        do {
            let files = try fileManager.contentsOfDirectory(at: captureFolderURL,
                                                         includingPropertiesForKeys: nil)
            for file in files {
                try fileManager.removeItem(at: file)
            }
            currentStorageSize = 0
            imageIndex = 0
            lastCaptureTime = 0
            os_log("Cleaned up capture directory", log: logger, type: .info)
        } catch {
            os_log("Error cleaning capture directory: %@", log: logger, type: .error, error.localizedDescription)
        }
    }

    private func ensureStorageLimit() {
        let maxBytes = Int64(maxStorageMB) * 1_048_576
        guard currentStorageSize > maxBytes else { return }
        
        DispatchQueue.main.async {
            self.delegate?.scanCaptureManagerReachedStorageLimit(self)
        }
    }
}

extension simd_float4 {
    var xyz: SIMD3<Float> {
        return SIMD3<Float>(x, y, z)
    }
}

extension ARCamera.TrackingState {
    var motionBlurEstimate: Float? {
        guard case .limited(let reason) = self else { return nil }
        if reason == .excessiveMotion { return 1.0 }
        return nil
    }
}

@available(iOS 13.4, *)
class ModelViewController: UIViewController, QLPreviewControllerDataSource, UIDocumentPickerDelegate {
    var capturedMeshes: [CapturedMesh] = []
    private let sceneView = SCNView()
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var modelUrl: URL?
    private var downloadedFileURL: URL?
    
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
        button.isHidden = true
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
        button.isHidden = true
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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupScene()
    }
    
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
                    self.showErrorAlertWithLink(message: "API request failed: \(error.localizedDescription)")
                    self.statusLabel.text = "Processing failed."
                    self.endBackgroundTask()
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                os_log("❌ API returned non-200 status: %d", log: .default, type: .error, statusCode)
                DispatchQueue.main.async {
                    self.showErrorAlertWithLink(message: "API returned status code: \(statusCode)")
                    self.statusLabel.text = "Processing failed."
                    self.endBackgroundTask()
                }
                return
            }
            
            guard let data = data else {
                os_log("❌ No data received from API", log: .default, type: .error)
                DispatchQueue.main.async {
                    self.showErrorAlertWithLink(message: "No data received from API")
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
                        self.showErrorAlertWithLink(message: "Invalid model URL in response")
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
                    self.showErrorAlertWithLink(message: "Failed to parse API response: \(error.localizedDescription)")
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
    
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return downloadedFileURL != nil ? 1 : 0
    }
    
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return downloadedFileURL! as NSURL
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        statusLabel.text = "Model saved successfully."
        generateHapticFeedback()
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        statusLabel.text = "Download cancelled."
    }
    
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
    
    private func generateHapticFeedback(_ type: UINotificationFeedbackGenerator.FeedbackType = .success) {
        let feedbackGenerator = UINotificationFeedbackGenerator()
        feedbackGenerator.prepare()
        feedbackGenerator.notificationOccurred(type)
    }
}

@available(iOS 13.4, *)
protocol ControlPanelDelegate: AnyObject {
    func controlPanelDidTapToggleScan(_ panel: ControlPanel)
    func controlPanelDidTapRestart(_ panel: ControlPanel)
}

@available(iOS 13.4, *)
class ControlPanel: UIStackView {
    let statusLabel = UILabel()
    let actionButtons = UIStackView()
    
    let toggleScanButton = UIButton()
    let restartButton = UIButton()
    
    weak var delegate: ControlPanelDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupButtonActions()
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupButtonActions()
    }
    
    private func setupUI() {
        axis = .vertical
        spacing = 12
        distribution = .fill
        
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 16, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        statusLabel.layer.cornerRadius = 8
        statusLabel.clipsToBounds = true
        statusLabel.text = "Ready to scan"
        addArrangedSubview(statusLabel)
        statusLabel.heightAnchor.constraint(equalToConstant: 44).isActive = true
        
        actionButtons.axis = .horizontal
        actionButtons.spacing = 12
        actionButtons.distribution = .fillProportionally
        addArrangedSubview(actionButtons)
        actionButtons.heightAnchor.constraint(equalToConstant: 50).isActive = true
        
        configureButton(toggleScanButton, title: "Start", color: .systemGreen)
        configureButton(restartButton, title: "Restart", color: .systemOrange)
        
        toggleScanButton.widthAnchor.constraint(equalToConstant: 100).isActive = true
        restartButton.widthAnchor.constraint(equalToConstant: 100).isActive = true
        
        updateUIForScanningState(isScanning: false, hasMeshes: false)
    }
    
    private func configureButton(_ button: UIButton, title: String, color: UIColor) {
        button.setTitle(title, for: .normal)
        button.backgroundColor = color.withAlphaComponent(0.8)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.clipsToBounds = true
        actionButtons.addArrangedSubview(button)
    }
    
    private func setupButtonActions() {
        toggleScanButton.addTarget(self, action: #selector(toggleScanTapped), for: .touchUpInside)
        restartButton.addTarget(self, action: #selector(restartTapped), for: .touchUpInside)
    }
    
    @objc private func toggleScanTapped() {
        delegate?.controlPanelDidTapToggleScan(self)
    }
    
    @objc private func restartTapped() {
        delegate?.controlPanelDidTapRestart(self)
    }
    
    func updateStatus(_ text: String) {
        DispatchQueue.main.async {
            self.statusLabel.text = text
        }
    }
    
    func updateUIForScanningState(isScanning: Bool, hasMeshes: Bool) {
        DispatchQueue.main.async {
            self.toggleScanButton.setTitle(isScanning ? "Stop" : "Start", for: .normal)
            self.toggleScanButton.backgroundColor = isScanning ? UIColor.systemRed.withAlphaComponent(0.8) : UIColor.systemGreen.withAlphaComponent(0.8)
            self.restartButton.isHidden = !hasMeshes || isScanning
        }
    }
}

extension UIView {
    var parentViewController: UIViewController? {
        var parentResponder: UIResponder? = self
        while parentResponder != nil {
            parentResponder = parentResponder?.next
            if let viewController = parentResponder as? UIViewController {
                return viewController
            }
        }
        return nil
    }
}

class LocationManager: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    var latestLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        latestLocation = locations.last
    }
}

struct CapturedMesh: Codable {
    var vertices: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
    var indices: [UInt32]
    var transform: [[Float]]
    
    init(vertices: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32], transform: simd_float4x4) {
        self.vertices = vertices
        self.normals = normals
        self.indices = indices
        self.transform = transform.toArray()
    }
    
    init(vertices: [SIMD3<Float>], indices: [UInt32], transform: simd_float4x4) {
        self.vertices = vertices
        self.normals = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: vertices.count)
        self.indices = indices
        self.transform = transform.toArray()
    }
    
    func getTransform() -> simd_float4x4 {
        return simd_float4x4(self.transform)
    }
    
    func exportAsPLY() -> String {
        var header = """
        ply
        format ascii 1.0
        comment Generated from LiDAR scan
        element vertex \(vertices.count)
        property float x
        property float y
        property float z
        property float nx
        property float ny
        property float nz
        element face \(indices.count / 3)
        property list uchar uint vertex_indices
        end_header\n\n
        """
        
        var body = ""
        for i in 0..<vertices.count {
            let v = vertices[i]
            let n = normals[i]
            body += "\(v.x) \(v.y) \(v.z) \(n.x) \(n.y) \(n.z)\n"
        }
        
        for i in stride(from: 0, to: indices.count, by: 3) {
            body += "3 \(indices[i]) \(indices[i+1]) \(indices[i+2])\n"
        }
        
        return header + body
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
