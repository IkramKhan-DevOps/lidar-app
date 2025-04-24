import UIKit
import SceneKit

class ModelViewController: UIViewController {

    // MARK: - UI Components
    private let sceneView = SCNView()
    private let closeButton = UIButton(type: .system)

    // MARK: - Properties
    var capturedMeshes: [CapturedMesh] = []

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupGestures()
        loadModel()
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .black

        // Scene View
        sceneView.frame = view.bounds
        sceneView.backgroundColor = .black
        sceneView.autoenablesDefaultLighting = true
        sceneView.allowsCameraControl = true
        view.addSubview(sceneView)

        // Close Button
        closeButton.setTitle("Close", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        closeButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.8)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.layer.cornerRadius = 10
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.frame = CGRect(x: 20, y: 50, width: 80, height: 44)
        view.addSubview(closeButton)
    }

    // MARK: - Gestures
    private func setupGestures() {
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        sceneView.addGestureRecognizer(pinchGesture)
        sceneView.addGestureRecognizer(panGesture)
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
        centerModel()
    }

    private func createGeometry(from mesh: CapturedMesh) -> SCNGeometry {
        // Convert vertices to SCNVector3
        let vertices = mesh.vertices.map { SCNVector3($0) }
        let vertexSource = SCNGeometrySource(vertices: vertices)

        // Create geometry elements
        let element = SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)

        // Create material
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white.withAlphaComponent(0.8)
        material.lightingModel = .physicallyBased

        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
        geometry.materials = [material]
        return geometry
    }

    private func centerModel() {
        guard let scene = sceneView.scene else { return }
        
        // Get the bounding box of all nodes
        var minVec = SCNVector3Zero
        var maxVec = SCNVector3Zero
        
        scene.rootNode.childNodes.forEach { node in
            let (nodeMin, nodeMax) = node.boundingBox
            minVec.x = min(minVec.x, nodeMin.x)
            minVec.y = min(minVec.y, nodeMin.y)
            minVec.z = min(minVec.z, nodeMin.z)
            maxVec.x = max(maxVec.x, nodeMax.x)
            maxVec.y = max(maxVec.y, nodeMax.y)
            maxVec.z = max(maxVec.z, nodeMax.z)
        }
        
        let bound = SCNVector3(
            x: maxVec.x - minVec.x,
            y: maxVec.y - minVec.y,
            z: maxVec.z - minVec.z
        )
        
        let center = SCNVector3(
            x: minVec.x + bound.x/2,
            y: minVec.y + bound.y/2,
            z: minVec.z + bound.z/2
        )
        
        // Create and position camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        
        // Position camera based on model size
        let maxDimension = max(bound.x, max(bound.y, bound.z))
        let cameraDistance = maxDimension * 1.5
        
        cameraNode.position = SCNVector3(
            x: center.x,
            y: center.y,
            z: center.z + cameraDistance
        )
        
        // Make camera look at center of model
        cameraNode.look(at: center)
        
        scene.rootNode.addChildNode(cameraNode)
        sceneView.pointOfView = cameraNode
    }

    // MARK: - Gesture Handlers
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let camera = sceneView.pointOfView?.camera else { return }
        let newZoom = camera.fieldOfView / gesture.scale
        camera.fieldOfView = min(max(newZoom, 10), 120) // Constrain zoom range
        gesture.scale = 1
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: sceneView)
        let rotationAngle = Float(translation.x) * .pi / 180.0
        sceneView.pointOfView?.eulerAngles.y -= rotationAngle
        gesture.setTranslation(.zero, in: sceneView)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}
