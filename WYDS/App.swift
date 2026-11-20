import UIKit
import UserNotifications
import GoogleSignIn

/* wYDS iPhone uygulaması: wyds.com.tr'yi uygulama içinde açar (Android sürümünün eşi).
   Site, WydsNative köprüsüyle telefonun özelliklerini kullanır:
   Google ve Apple ile giriş, yedek dosyası kaydetme, üst/alt çubuk renkleri, hatırlatma bildirimleri. */
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = Notif.shared
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: "Default Configuration", sessionRole: session.role)
        c.delegateClass = SceneDelegate.self
        return c
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    let web = WebViewController()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: ws)
        w.rootViewController = web
        w.makeKeyAndVisible()
        window = w
        Notif.shared.open = { [weak self] url in self?.web.load(url) }
        /* wyds.com.tr bağlantısıyla açıldıysa o sayfaya git */
        if let u = options.userActivities.first?.webpageURL, WebViewController.isOurs(u) { web.pendingURL = u }
        if let u = options.urlContexts.first?.url { _ = GIDSignIn.sharedInstance.handle(u) }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for c in URLContexts { _ = GIDSignIn.sharedInstance.handle(c.url) }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        if let u = userActivity.webpageURL, WebViewController.isOurs(u) { web.load(u) }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        Notif.shared.clearShown() /* uygulama açıldı: bekleyen hatırlatma kalksın */
        web.refreshNotifState()
    }
}
