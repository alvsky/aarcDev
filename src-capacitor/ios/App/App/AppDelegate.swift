import UIKit
import Capacitor
import Firebase
import FirebaseMessaging

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    var window: UIWindow?
    var pendingFCMToken: String?

    // MARK: - App Lifecycle

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        FirebaseApp.configure()
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.webViewDidLoad),
            name: Notification.Name("CAPNotificationDidLoad"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.handleFCMToken(_:)),
            name: Notification.Name("FCMToken"),
            object: nil
        )
        
        return true
    }

    // MARK: - Helpers

    private func getRootViewController() -> CAPBridgeViewController? {
        guard let scene   = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window  = scene.windows.first,
              let rootVC  = window.rootViewController as? CAPBridgeViewController else {
            return nil
        }
        return rootVC
    }

    // Zamijeni sendTokenToJS funkciju
    func sendTokenToJS(_ token: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if let rootVC = self.getRootViewController() {
                let js = "localStorage.setItem('fcmToken', '\(token)');"
                rootVC.webView?.evaluateJavaScript(js) { result, error in
                    if let error = error {
                        print("JS eval error: \(error)")
                    } else {
                        print("FCM token saved to localStorage")
                    }
                }
            }
        }
    }

    // MARK: - Notifications / Observers

    @objc func webViewDidLoad() {
        if let token = pendingFCMToken {
            sendTokenToJS(token)
            pendingFCMToken = nil
        }
    }

    @objc func handleFCMToken(_ notification: Notification) {
        if let token = notification.userInfo?["token"] as? String {
            print("FCM Token in AppDelegate: \(token)")
            UserDefaults.standard.set(token, forKey: "FCMToken")
        }
    }

    // MARK: - Firebase Messaging

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("FCM Token received: \(token)")
        
        UserDefaults.standard.set(token, forKey: "FCMToken")
        
        NotificationCenter.default.post(
            name: Notification.Name("FCMToken"),
            object: nil,
            userInfo: ["token": token]
        )
        
        pendingFCMToken = token
        sendTokenToJS(token)
        


    }

    // MARK: - APNs

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        NotificationCenter.default.post(name: .capacitorDidRegisterForRemoteNotifications, object: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .capacitorDidFailToRegisterForRemoteNotifications, object: error)
    }

    // MARK: - UNUserNotificationCenter

    func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    // MARK: - Capacitor

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }

    // MARK: - Standard lifecycle

    func applicationWillResignActive(_ application: UIApplication) {}
    func applicationDidEnterBackground(_ application: UIApplication) {}
    func applicationWillEnterForeground(_ application: UIApplication) {}
    func applicationDidBecomeActive(_ application: UIApplication) {}
    func applicationWillTerminate(_ application: UIApplication) {}
}
