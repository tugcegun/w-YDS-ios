/* Sayfaya en başta eklenen köprü: Android'deki WydsNative ile aynı adlar.
   Site (cloud.js, app.js, bildirim.js) iki telefonda da aynı kodla çalışır.
   iPhone'da mesajlar tek yönlü gider; sonuçlar window.__wydsGoogle / __wydsApple / __wydsNotif ile geri gelir. */
enum Bridge {
    static let js = """
    (function(){
      if (window.WydsNative) return;
      var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.wyds;
      if (!h) return;
      function send(a, b) { h.postMessage({ a: a, b: b === undefined ? null : b }); }
      window.WydsNative = {
        platform: "ios",
        _notif: "default",
        googleSignIn: function () { send("googleSignIn"); },
        appleSignIn: function () { send("appleSignIn"); },
        signOut: function () { send("signOut"); },
        setBars: function (t, b) { send("setBars", [String(t), String(b)]); },
        saveFile: function (n, c) { send("saveFile", [String(n), String(c)]); },
        notifState: function () { return window.WydsNative._notif; },
        notifAsk: function () { send("notifAsk"); },
        notifPlan: function (j) { send("notifPlan", String(j)); },
        openExternal: function (u) { send("openExternal", String(u)); },
        retry: function () { send("retry"); }
      };
    })();
    """
}
