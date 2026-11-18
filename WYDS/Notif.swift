import UIKit
import UserNotifications

/* Hatırlatma bildirimleri. Site (js/bildirim.js) önümüzdeki günlerin planını verir:
   [{t: zaman (ms), title, body, tag}]. Her biri telefonda zamanlanır; yeni plan gelince eskisi tümüyle silinir.
   Sunucu yoktur. iPhone zamanlanmış bildirimleri yeniden başlatmada da kendisi saklar. */
final class Notif: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notif()
    static let prefix = "wyds-plan-"
    static let max = 24
    let center = UNUserNotificationCenter.current()
    /* bildirime dokunulunca açılacak adres (SceneDelegate bağlar) */
    var open: ((URL) -> Void)?

    func state(_ done: @escaping (String) -> Void) {
        center.getNotificationSettings { s in
            let ok = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
                || s.authorizationStatus == .ephemeral
            DispatchQueue.main.async { done(ok ? "granted" : (s.authorizationStatus == .notDetermined ? "default" : "denied")) }
        }
    }

    /* izin ister; daha önce reddedildiyse telefonun bu uygulamaya ait ayarını açar */
    func ask(_ done: @escaping (Bool) -> Void) {
        center.getNotificationSettings { s in
            switch s.authorizationStatus {
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
                    DispatchQueue.main.async { done(ok) }
                }
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async { done(true) }
            default:
                DispatchQueue.main.async {
                    var str = UIApplication.openSettingsURLString
                    if #available(iOS 16.0, *) { str = UIApplication.openNotificationSettingsURLString }
                    if let u = URL(string: str) { UIApplication.shared.open(u) }
                }
            }
        }
    }

    func setPlan(_ json: String) {
        guard let data = json.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return }
        center.getPendingNotificationRequests { reqs in
            let old = reqs.map(\.identifier).filter { $0.hasPrefix(Notif.prefix) }
            self.center.removePendingNotificationRequests(withIdentifiers: old)
            let now = Date()
            for (i, o) in arr.prefix(Notif.max).enumerated() {
                guard let ms = (o["t"] as? NSNumber)?.doubleValue else { continue }
                let when = Date(timeIntervalSince1970: ms / 1000)
                if when <= now { continue }
                let c = UNMutableNotificationContent()
                c.title = o["title"] as? String ?? "w YDS"
                c.body = o["body"] as? String ?? ""
                c.sound = .default
                c.threadIdentifier = "hatirlatma"
                c.userInfo = ["tag": o["tag"] as? String ?? ""]
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: when)
                let trig = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                self.center.add(UNNotificationRequest(identifier: Notif.prefix + String(i), content: c, trigger: trig))
            }
        }
    }

    func clearShown() {
        center.removeAllDeliveredNotifications()
        if #available(iOS 16.0, *) { center.setBadgeCount(0) }
    }

    /* uygulama açıkken gelirse de göster (Android'deki gibi) */
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }

    /* bildirime dokunuldu: ilgili sayfayla aç (site ?ntf=yanlis / kelime parametresini okur) */
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let tag = response.notification.request.content.userInfo["tag"] as? String ?? ""
        var s = WebViewController.start.absoluteString
        if !tag.isEmpty, let e = tag.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) { s += "&ntf=" + e }
        if let u = URL(string: s) { DispatchQueue.main.async { self.open?(u) } }
        done()
    }
}
