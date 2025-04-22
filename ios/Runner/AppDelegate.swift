import UIKit
import Flutter
import ARKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
        let channel = FlutterMethodChannel(name: "com.demo.channel/message",
                                           binaryMessenger: controller.binaryMessenger)
        
        channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            if call.method == "startScan" {
                self?.startLiDARScan(result: result)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func startLiDARScan(result: @escaping FlutterResult) {
        if #available(iOS 13.4, *) {
            guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) else {
                result("Scene reconstruction not supported on this device.")
                return
            }

            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal, .vertical]
            config.environmentTexturing = .automatic
            config.sceneReconstruction = .meshWithClassification

            let arSession = ARSession()
            arSession.run(config)

            print("Started LiDAR scan session.")
            result("LiDAR scan started.")
        } else {
            result("Scene reconstruction requires iOS 13.4 or newer.")
        }
    }
}
