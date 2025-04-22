import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "com.demo.channel/message",
                                       binaryMessenger: controller.binaryMessenger)

    channel.setMethodCallHandler { (call, result) in
      if call.method == "getMessage" {
        result("Hello from Swift!")
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
