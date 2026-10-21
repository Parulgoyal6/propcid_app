import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Same key already used by android/app/src/main/AndroidManifest.xml's
    // com.google.android.geo.API_KEY and the Flutter .env's
    // GOOGLE_MAPS_API_KEY. `google_maps_flutter`'s GoogleMap widget rendered
    // nothing on iOS before this call — there was no key wired up for this
    // platform at all.
    GMSServices.provideAPIKey("AIzaSyDEWPGxpf3Tb_xoUVu34qfhscsZjTX5oGo")
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
