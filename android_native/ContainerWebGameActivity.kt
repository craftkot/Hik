package com.ehtid.game_lab

import android.app.Activity
import android.os.Bundle
import android.webkit.MimeTypeMap
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileInputStream

/**
 * Web/HTML5 proof-of-concept: files in EHTID private storage and isolated
 * per-game HTTPS origins. No JS bridge, filesystem URL access or external
 * navigation. This DOES NOT run imported Android APK code.
 */
class ContainerWebGameActivity : Activity() {
    private var webView: WebView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val id = intent.getStringExtra("gameId") ?: run { finish(); return }
        val root = try { ContainerStore(this).webRoot(id).canonicalFile }
                   catch (_: Exception) { finish(); return }
        val originHost = "$id.ehtid-game.invalid"
        val prefix = root.canonicalPath + File.separator
        val browser = WebView(this)
        webView = browser
        browser.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
            mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
        }
        browser.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView,
                request: WebResourceRequest): Boolean {
                val url = request.url
                return url.scheme != "https" || url.host != originHost
            }

            override fun shouldInterceptRequest(view: WebView,
                request: WebResourceRequest): WebResourceResponse {
                val url = request.url
                if (url.scheme != "https" || url.host != originHost) {
                    return blocked()
                }
                val path = url.path?.removePrefix("/")?.ifEmpty { "index.html" }
                    ?: "index.html"
                val file = try { File(root, path).canonicalFile }
                           catch (_: Exception) { return blocked() }
                if (!file.path.startsWith(prefix) || !file.isFile) return blocked()
                val extension = file.extension.lowercase()
                val mime = when (extension) {
                    "js", "mjs" -> "application/javascript"
                    "wasm" -> "application/wasm"
                    "json" -> "application/json"
                    "svg" -> "image/svg+xml"
                    "html" -> "text/html"
                    "css" -> "text/css"
                    else -> MimeTypeMap.getSingleton()
                        .getMimeTypeFromExtension(extension)
                        ?: "application/octet-stream"
                }
                return try {
                    WebResourceResponse(mime, "UTF-8", FileInputStream(file))
                } catch (_: Exception) { blocked() }
            }
        }
        setContentView(browser)
        browser.loadUrl("https://$originHost/index.html")
    }

    private fun blocked() = WebResourceResponse(
        "text/plain", "UTF-8", ByteArrayInputStream(ByteArray(0)))

    @Deprecated("Use newer back dispatch for future revisions")
    override fun onBackPressed() {
        if (webView?.canGoBack() == true) webView?.goBack()
        else super.onBackPressed()
    }

    override fun onDestroy() {
        webView?.apply {
            stopLoading()
            loadUrl("about:blank")
            destroy()
        }
        webView = null
        super.onDestroy()
    }
}
