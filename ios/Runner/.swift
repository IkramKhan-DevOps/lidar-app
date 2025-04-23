import UIKit
import ARKit
import SceneKit

class ScanViewController: UIViewController, ARSessionDelegate {

    var arView: ARSCNView!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupARView()
        startScan()
    }

    func setupARView() {
        arView = ARSCNView(frame: view.bounds)
        view.addSubview(arView)
        arView.delegate = self
        arView.session.delegate = self
        arView.automaticallyUpdatesLighting = true
    }

    func startScan() {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) else {
            print("Scene reconstruction not supported")
            return
        }

        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .meshWithClassification
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        arView.session.run(config)
        print("Started scanning...")
    }
}
