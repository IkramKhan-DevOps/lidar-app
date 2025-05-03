import UIKit
import Flutter
import ARKit
import CoreLocation

@main
@objc class AppDelegate: FlutterAppDelegate {
    
    var locationManager: LocationManager?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        locationManager = LocationManager()

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
        DispatchQueue.main.async {
            if #available(iOS 13.4, *) {
                let scanVC = ScanViewController()
                scanVC.modalPresentationStyle = .fullScreen
                self.window?.rootViewController?.present(scanVC, animated: true) {
                    result("LiDAR Scan View started.")
                }
            } else {
                result(FlutterError(
                    code: "UNSUPPORTED",
                    message: "LiDAR scanning requires iOS 13.4 or later",
                    details: nil
                ))
            }
        }
    }
}
