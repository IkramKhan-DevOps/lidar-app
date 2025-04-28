import UIKit
import Flutter

class SceneDelegate: FlutterSceneDelegate {
    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Create a new window
        let window = UIWindow(windowScene: windowScene)

        // Get the Flutter engine from AppDelegate or create a new one
        let flutterEngine = (UIApplication.shared.delegate as? FlutterAppDelegate)?.flutterEngine ?? FlutterEngine(name: "my flutter engine")

        // Initialize FlutterViewController
        let flutterViewController = FlutterViewController(engine: flutterEngine, nibName: nil, bundle: nil)

        // Set up window
        window.rootViewController = flutterViewController
        self.window = window
        window.makeKeyAndVisible()

        // Re-setup method channel in case AppDelegate's window was not initialized
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.setupFlutterMethodChannel()
        }
    }
}
