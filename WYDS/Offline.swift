/* İnternet yokken gösterilen sayfa */
enum Offline {
    static let html = """
    <!doctype html><html lang="tr"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <style>
    :root{color-scheme:light dark}
    body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
    font-family:-apple-system,system-ui,sans-serif;background:#F4EFE7;color:#1d1d1d;text-align:center;padding:24px;box-sizing:border-box}
    @media (prefers-color-scheme:dark){body{background:#141414;color:#F8DE8D}}
    h1{font-size:20px;margin:0 0 8px}p{margin:0 0 20px;opacity:.8;line-height:1.5}
    button{font:inherit;font-weight:600;border:0;border-radius:12px;padding:12px 24px;background:#006B54;color:#fff}
    </style></head><body><div>
    <h1>İnternet bağlantısı yok</h1>
    <p>wYDS'yi açmak için internete bağlan, sonra tekrar dene.</p>
    <button onclick="WydsNative.retry()">Tekrar dene</button>
    </div></body></html>
    """
}
