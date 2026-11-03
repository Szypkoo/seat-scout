package seat.scout

import android.annotation.SuppressLint
import android.app.Application
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.CookieManager
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.json.JSONObject

class AndroidWebSession(private val context: Context) {
    private var webView: WebView? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var isReady = false
    private val readySignal = CompletableDeferred<Boolean>()

    companion object {
        private const val TAG = "SeatScout-Net"
        private const val BASE_URL = "https://ebilet.intercity.pl"

        @Volatile
        var sharedContext: Context? = null

        @Volatile
        private var sharedSessionInstance: AndroidWebSession? = null

        fun getShared(): AndroidWebSession {
            return sharedSessionInstance ?: synchronized(this) {
                sharedSessionInstance ?: run {
                    val ctx = sharedContext ?: runCatching {
                        val actThread = Class.forName("android.app.ActivityThread")
                        actThread.getMethod("currentApplication").invoke(null) as? Application
                    }.getOrNull() ?: error("Android Context not available for WebSession")
                    AndroidWebSession(ctx).also {
                        it.start()
                        sharedSessionInstance = it
                    }
                }
            }
        }

        fun executeFetchSync(method: String, url: String, body: String?): Pair<Int, ByteArray>? {
            return runBlocking {
                getShared().executeFetch(method, url, body)
            }
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    fun start() {
        if (webView != null) return

        mainHandler.post {
            try {
                val wv = WebView(context.applicationContext)
                val settings = wv.settings
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.databaseEnabled = true
                settings.cacheMode = WebSettings.LOAD_DEFAULT

                CookieManager.getInstance().setAcceptCookie(true)
                CookieManager.getInstance().setAcceptThirdPartyCookies(wv, true)

                wv.webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView?, url: String?) {
                        Log.i(TAG, "Akamai page loaded: $url")
                        isReady = true
                        readySignal.complete(true)
                    }

                    override fun onReceivedError(
                        view: WebView?,
                        errorCode: Int,
                        description: String?,
                        failingUrl: String?
                    ) {
                        Log.w(TAG, "WebView error: $description for $failingUrl")
                    }
                }

                Log.i(TAG, "Ładuję ebilet.intercity.pl (sesja Akamai)...")
                wv.loadUrl(BASE_URL)
                webView = wv
            } catch (e: Exception) {
                Log.e(TAG, "Błąd inicjalizacji WebView: ${e.message}")
                readySignal.complete(false)
            }
        }
    }

    suspend fun executeFetch(
        method: String,
        url: String,
        body: String?
    ): Pair<Int, ByteArray>? {
        start()
        if (!isReady) {
            readySignal.await()
            delay(1500) // Wait for Akamai scripts to initialize cookies
        }

        val jsonBody = if (body != null) JSONObject.quote(body) else "null"
        val script = """
            (async function() {
                const ctrl = new AbortController();
                const timer = setTimeout(() => ctrl.abort(), 12000);
                const opts = { method: "$method", headers: {}, signal: ctrl.signal };
                const b = $jsonBody;
                if (b) { opts.headers["Content-Type"] = "application/json"; opts.body = b; }
                try {
                    const r = await fetch("$url", opts);
                    const text = await r.text();
                    clearTimeout(timer);
                    return JSON.stringify({ status: r.status, text: text });
                } catch (e) {
                    clearTimeout(timer);
                    return JSON.stringify({ status: 0, text: "" });
                }
            })();
        """.trimIndent()

        val deferred = CompletableDeferred<Pair<Int, ByteArray>?>()

        mainHandler.post {
            val wv = webView
            if (wv == null) {
                deferred.complete(null)
                return@post
            }

            wv.evaluateJavascript(script) { resultJson ->
                try {
                    val cleanJson = if (resultJson != null && resultJson.startsWith("\"") && resultJson.endsWith("\"")) {
                        JSONObject("{\"v\":$resultJson}").getString("v")
                    } else {
                        resultJson ?: ""
                    }

                    if (cleanJson.isEmpty() || cleanJson == "null") {
                        deferred.complete(null)
                        return@evaluateJavascript
                    }

                    val obj = JSONObject(cleanJson)
                    val status = obj.optInt("status", 0)
                    val text = obj.optString("text", "")
                    if (status == 0) {
                        deferred.complete(null)
                    } else {
                        deferred.complete(Pair(status, text.toByteArray(Charsets.UTF_8)))
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Błąd parsowania odpowiedzi z JS: ${e.message}")
                    deferred.complete(null)
                }
            }
        }

        return deferred.await()
    }
}
