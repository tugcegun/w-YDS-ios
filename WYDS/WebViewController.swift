import UIKit
import WebKit
import AuthenticationServices
import CryptoKit
import GoogleSignIn

final class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler,
    ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    static let start = URL(string: "https://wyds.com.tr/?kaynak=uygulama")!
    /* Uygulamanın içinde açılan adresler; diğer bağlantılar Safari'de açılır */
    static let hosts: Set<String> = ["wyds.com.tr", "www.wyds.com.tr", "w-yds-b3885.web.app", "w-yds-b3885.firebaseapp.com"]

    static func isOurs(_ u: URL?) -> Bool {
        guard let u = u, u.scheme == "https", let h = u.host else { return false }
        return hosts.contains(h)
    }

    var web: WKWebView!
    let topBar = UIView(), bottomBar = UIView()
    var splash: UIView?
    var pendingURL: URL?
    var lightTop = true
    var appleNonce: String?
    var notifState = "default"

    static let zemin = UIColor(named: "LaunchBackground") ?? UIColor(red: 0.957, green: 0.937, blue: 0.906, alpha: 1)

    override var preferredStatusBarStyle: UIStatusBarStyle { lightTop ? .darkContent : .lightContent }

    /* site renk vermeden önce (açılış, internet yok sayfası) saat/pil yazısı telefonun temasına uysun */
    var pageSetBars = false
    func followSystemBars() {
        guard !pageSetBars else { return }
        lightTop = traitCollection.userInterfaceStyle != .dark
        setNeedsStatusBarAppearanceUpdate()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        guard traitCollection.userInterfaceStyle != previous?.userInterfaceStyle else { return }
        followSystemBars()
        /* site "telefona göre" temadaysa çubuk rengini yeniden göndersin */
        web?.evaluateJavaScript("typeof syncBars==='function'&&setTimeout(syncBars,350)", completionHandler: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        followSystemBars()
        view.backgroundColor = Self.zemin
        topBar.backgroundColor = Self.zemin
        bottomBar.backgroundColor = Self.zemin
        lightTop = traitCollection.userInterfaceStyle != .dark

        let cfg = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        ucc.addUserScript(WKUserScript(source: Bridge.js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ucc.add(WeakHandler(self), name: "wyds")
        cfg.userContentController = ucc
        cfg.websiteDataStore = .default()
        cfg.allowsInlineMediaPlayback = true
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"
        cfg.applicationNameForUserAgent = "Mobile/15E148 WydsApp/\(ver) iOS"

        web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsLinkPreview = false
        web.isOpaque = false
        web.backgroundColor = Self.zemin
        web.scrollView.backgroundColor = Self.zemin
        web.scrollView.contentInsetAdjustmentBehavior = .never

        for v in [topBar, web!, bottomBar] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.bottomAnchor.constraint(equalTo: g.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            web.topAnchor.constraint(equalTo: g.topAnchor),
            web.bottomAnchor.constraint(equalTo: g.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: g.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: g.trailingAnchor),
            bottomBar.topAnchor.constraint(equalTo: g.bottomAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        /* soldan kaydırma = geri (Android'deki geri tuşunun karşılığı) */
        let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgeBack(_:)))
        edge.edges = .left
        view.addGestureRecognizer(edge)

        showSplash()
        refreshNotifState()
        web.load(URLRequest(url: pendingURL ?? Self.start))
        pendingURL = nil
    }

    /* açılış ekranı: site ilk kez yüklenene kadar (en çok 6 sn) kedi görünür */
    func showSplash() {
        let s = UIView()
        s.backgroundColor = Self.zemin
        let img = UIImageView(image: UIImage(named: "LaunchLogo"))
        img.contentMode = .scaleAspectFit
        img.translatesAutoresizingMaskIntoConstraints = false
        s.addSubview(img)
        s.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(s)
        NSLayoutConstraint.activate([
            s.topAnchor.constraint(equalTo: view.topAnchor), s.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            s.leadingAnchor.constraint(equalTo: view.leadingAnchor), s.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            img.centerXAnchor.constraint(equalTo: s.centerXAnchor), img.centerYAnchor.constraint(equalTo: s.centerYAnchor),
        ])
        splash = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.hideSplash() }
    }

    func hideSplash() {
        guard let s = splash else { return }
        splash = nil
        UIView.animate(withDuration: 0.25, animations: { s.alpha = 0 }, completion: { _ in s.removeFromSuperview() })
    }

    func load(_ url: URL) {
        if web == nil { pendingURL = url; return }
        web.load(URLRequest(url: url))
    }

    // MARK: - JS'e sonuç gönderme

    /* window[fn](...args) — değerler JSON olarak güvenle aktarılır */
    func callJS(_ fn: String, _ args: [Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: args), let a = String(data: d, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.\(fn)&&window.\(fn).apply(null,\(a))", completionHandler: nil)
    }

    func refreshNotifState() {
        Notif.shared.state { [weak self] st in
            guard let self = self else { return }
            self.notifState = st
            self.web?.evaluateJavaScript("window.WydsNative&&(window.WydsNative._notif=\"\(st)\")", completionHandler: nil)
        }
    }

    // MARK: - Köprü mesajları

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any],
              let act = body["a"] as? String else { return }
        let arg = body["b"]
        if act == "retry" { web.load(URLRequest(url: Self.start)); return }
        /* köprü yalnız kendi sitemizdeyken çalışır */
        guard Self.hosts.contains(message.frameInfo.securityOrigin.host) else { return }
        switch act {
        case "googleSignIn": googleSignIn()
        case "appleSignIn": appleSignIn()
        case "signOut": GIDSignIn.sharedInstance.signOut()
        case "setBars":
            if let p = arg as? [String], p.count == 2 { setBars(p[0], p[1]) }
        case "saveFile":
            if let p = arg as? [String], p.count == 2 { saveFile(name: p[0], content: p[1]) }
        case "notifAsk":
            Notif.shared.ask { [weak self] ok in
                self?.refreshNotifState()
                self?.callJS("__wydsNotif", [ok ? "granted" : "denied"])
            }
        case "notifPlan":
            if let j = arg as? String { Notif.shared.setPlan(j) }
        case "openExternal":
            if let s = arg as? String, let u = URL(string: s), ["http", "https"].contains(u.scheme ?? "") {
                UIApplication.shared.open(u)
            }
        default: break
        }
    }

    // MARK: - Çubuk renkleri

    /* "rgb(244, 239, 231)" → renk */
    static func cssColor(_ css: String) -> UIColor? {
        let p = css.components(separatedBy: CharacterSet(charactersIn: "0123456789.,").inverted).joined()
            .split(separator: ",").compactMap { Double($0) }
        guard p.count >= 3 else { return nil }
        return UIColor(red: p[0] / 255, green: p[1] / 255, blue: p[2] / 255, alpha: 1)
    }

    static func isLight(_ c: UIColor) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r + 0.587 * g + 0.114 * b) * 255 > 150
    }

    func setBars(_ top: String, _ bottom: String) {
        guard let t = Self.cssColor(top) else { return }
        let b = Self.cssColor(bottom) ?? t
        topBar.backgroundColor = t
        bottomBar.backgroundColor = b
        view.backgroundColor = t
        lightTop = Self.isLight(t)
        pageSetBars = true
        setNeedsStatusBarAppearanceUpdate()
    }

    // MARK: - Yedek dosyası

    func saveFile(name: String, content: String) {
        let clean = name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(clean.isEmpty ? "w-yds-yedek.json" : clean)
        do { try content.write(to: url, atomically: true, encoding: .utf8) } catch { toast("Yedek kaydedilemedi"); return }
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        present(picker, animated: true)
    }

    func toast(_ s: String) {
        let a = UIAlertController(title: nil, message: s, preferredStyle: .alert)
        present(a, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { a.dismiss(animated: true) }
    }

    // MARK: - Google ile giriş

    func googleSignIn() {
        GIDSignIn.sharedInstance.signIn(withPresenting: self) { [weak self] result, error in
            guard let self = self else { return }
            if let e = error as NSError? {
                if (error as? GIDSignInError)?.code == .canceled {
                    self.callJS("__wydsGoogle", [NSNull(), "cancel"])
                } else {
                    self.callJS("__wydsGoogle", [NSNull(), "Google girişi açılamadı (\(e.code))"])
                }
                return
            }
            guard let token = result?.user.idToken?.tokenString else {
                self.callJS("__wydsGoogle", [NSNull(), "Google hesabı okunamadı"]); return
            }
            self.callJS("__wydsGoogle", [token, NSNull()])
        }
    }

    // MARK: - Apple ile giriş (App Store kuralı 4.8)

    func appleSignIn() {
        let nonce = Self.randomNonce()
        appleNonce = nonce
        let req = ASAuthorizationAppleIDProvider().createRequest()
        req.requestedScopes = [.fullName, .email]
        req.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
        let c = ASAuthorizationController(authorizationRequests: [req])
        c.delegate = self
        c.presentationContextProvider = self
        c.performRequests()
    }

    static func randomNonce(_ n: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var out = ""
        var gen = SystemRandomNumberGenerator()
        for _ in 0..<n { out.append(chars[Int(gen.next() % UInt64(chars.count))]) }
        return out
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        view.window ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let c = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokData = c.identityToken, let token = String(data: tokData, encoding: .utf8),
              let nonce = appleNonce else {
            callJS("__wydsApple", [NSNull(), "Apple hesabı okunamadı"]); return
        }
        var name = ""
        if let f = c.fullName { name = PersonNameComponentsFormatter().string(from: f) }
        let code = c.authorizationCode.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        callJS("__wydsApple", [["idToken": token, "nonce": nonce, "name": name, "code": code], NSNull()])
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let canceled = (error as? ASAuthorizationError)?.code == .canceled
        callJS("__wydsApple", [NSNull(), canceled ? "cancel" : "Apple ile giriş açılamadı"])
    }

    // MARK: - Gezinme

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let u = action.request.url else { decisionHandler(.cancel); return }
        let scheme = u.scheme ?? ""
        if scheme == "about" || scheme == "data" || scheme == "blob" { decisionHandler(.allow); return }
        /* alt çerçeveler (Firebase giriş çerçevesi vb.) serbest; ana sayfa yalnız kendi sitemiz */
        if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        if Self.isOurs(u) { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        if ["http", "https", "mailto", "tel"].contains(scheme) { UIApplication.shared.open(u) }
    }

    /* target=_blank / window.open: kendi sitemizse aynı pencerede, değilse Safari'de */
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = action.request.url {
            if Self.isOurs(u) { webView.load(action.request) } else { UIApplication.shared.open(u) }
        }
        return nil
    }

    /* site içi alert / confirm / prompt (ör. hesap silme onayı) */
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Tamam", style: .default) { _ in completionHandler() })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Vazgeç", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "Tamam", style: .default) { _ in completionHandler(true) })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        a.addTextField { t in
            t.text = defaultText
            t.isSecureTextEntry = prompt.lowercased().contains("şifre")
        }
        a.addAction(UIAlertAction(title: "Vazgeç", style: .cancel) { _ in completionHandler(nil) })
        a.addAction(UIAlertAction(title: "Tamam", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hideSplash()
        refreshNotifState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let e = error as NSError
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
        if e.domain == "WebKitErrorDomain" && e.code == 102 { return } /* indirme vb. sayfa değişmedi */
        hideSplash()
        webView.loadHTMLString(Offline.html, baseURL: nil)
    }

    /* WebKit süreci çökerse (bellek) sayfayı yeniden aç */
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    @objc func edgeBack(_ g: UIScreenEdgePanGestureRecognizer) {
        guard g.state == .ended, g.translation(in: view).x > 60 else { return }
        web.evaluateJavaScript("(window.wydsBack&&window.wydsBack())?1:0") { [weak self] r, _ in
            guard let self = self else { return }
            if (r as? Int) == 1 { return }
            if self.web.canGoBack { self.web.goBack() }
        }
    }
}

/* WKUserContentController denetleyiciyi güçlü tutar; döngü olmasın diye ara nesne */
final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}
