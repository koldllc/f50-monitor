package com.kold.f50.monitor.android

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast

class MainActivity : Activity() {
    private lateinit var webView: WebView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AgentRuntime.initialize(this)
        startAgentService()

        webView = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = true
            settings.allowContentAccess = false
            settings.allowFileAccessFromFileURLs = false
            settings.allowUniversalAccessFromFileURLs = false
            settings.setSupportMultipleWindows(false)
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    return handleNavigation(request.url.toString())
                }

                @Suppress("DEPRECATION")
                override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean {
                    return handleNavigation(url)
                }
            }
            addJavascriptInterface(AndroidBridge(this@MainActivity), "F50Android")
            loadUrl("file:///android_asset/www/index.html")
        }
        setContentView(webView)
    }

    override fun onDestroy() {
        webView.removeJavascriptInterface("F50Android")
        webView.destroy()
        super.onDestroy()
    }

    private fun startAgentService() {
        val intent = Intent(this, F50AgentService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
    }

    private fun handleNavigation(url: String): Boolean {
        if (url.startsWith("file:///android_asset/www/")) return false
        if (url.startsWith("http://") || url.startsWith("https://")) {
            runCatching { startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url))) }
                .onFailure { Toast.makeText(this, "无法打开外部链接", Toast.LENGTH_SHORT).show() }
        }
        return true
    }

    private class AndroidBridge(private val activity: MainActivity) {
        @JavascriptInterface
        fun invoke(command: String, argsJson: String): String = AgentRuntime.invoke(activity, command, argsJson)
    }
}
