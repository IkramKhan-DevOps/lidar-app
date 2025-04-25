
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

        // Enable smooth camera motion (compatible)
        sceneView.defaultCameraController.inertiaEnabled = true
        sceneView.defaultCameraController.maximumVerticalAngle = 90
        sceneView.defaultCameraController.minimumVerticalAngle = -90

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

        // Position node at origin
        targetNode.position = SCNVector3(-center.x, -center.y, -center.z)

        // Position camera
        let maxDimension = max(bound.x, bound.y, bound.z)
        let cameraDistance = maxDimension * 2.0

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(center.x, center.y, center.z + cameraDistance)
        sceneView.scene?.rootNode.addChildNode(cameraNode)
        sceneView.pointOfView = cameraNode
    }

    // MARK: - Actions
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}
