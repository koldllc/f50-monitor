package com.kold.f50.monitor.android

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.graphics.Color
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import org.json.JSONObject

class MainActivity : Activity() {
    private var webView: WebView? = null
    private var fallbackView: TextView? = null
    private val fallbackHandler = Handler(Looper.getMainLooper())
    private val fallbackRefresh = object : Runnable {
        override fun run() {
            refreshFallback()
            fallbackHandler.postDelayed(this, FALLBACK_REFRESH_MS)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AgentRuntime.initialize(this)
        startAgentService()

        if (!WebViewProviderProbe.isAvailable()) {
            showFallback("系统未安装 WebView，已切换到原生状态界面。")
            return
        }

        webView = runCatching {
            WebView(this).apply {
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
        }.onFailure { error ->
            showFallback("系统 WebView 无法启动，已切换到原生状态界面。\n${error.javaClass.simpleName}")
        }.getOrNull()
        webView?.let(::setContentView)
    }

    override fun onDestroy() {
        fallbackHandler.removeCallbacks(fallbackRefresh)
        webView?.let {
            it.removeJavascriptInterface("F50Android")
            it.destroy()
        }
        webView = null
        super.onDestroy()
    }

    private fun showFallback(reason: String) {
        val scroll = ScrollView(this)
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(24), dp(20), dp(24))
            setBackgroundColor(Color.rgb(16, 19, 24))
        }
        fallbackView = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 15f
            setLineSpacing(0f, 1.25f)
            text = reason
        }
        container.addView(fallbackView, ViewGroup.LayoutParams(-1, -2))
        scroll.addView(container)
        setContentView(scroll)
        fallbackRefresh.run()
    }

    private fun refreshFallback() {
        val view = fallbackView ?: return
        val status = runCatching { JSONObject(AgentRuntime.invoke(this, "get_status", "{}")) }
            .getOrDefault(JSONObject())
        val info = runCatching { JSONObject(AgentRuntime.invoke(this, "get_agent_info", "{}")) }
            .getOrDefault(JSONObject())
        view.text = buildString {
            append("F50 Monitor\n\n")
            append("网络：").append(status.optString("networkType", "未知"))
                .append(" / ").append(status.optString("carrier", "未知")).append('\n')
            append("信号：").append(status.optInt("signalBar", 0)).append("/5\n")
            append("下载：").append(rate(status, "dlSpeed")).append('\n')
            append("上传：").append(rate(status, "ulSpeed")).append('\n')
            append("CPU：").append(percent(status, "cpuUsage")).append('\n')
            append("内存：").append(percent(status, "memUsage")).append('\n')
            append("温度：").append(status.optDouble("temperature", 0.0)).append(" °C\n")
            append("状态：").append(if (status.optBoolean("isOnline", false)) "在线" else "等待 Router 数据").append('\n')
            append("8787：").append(info.optString("host", "本机")).append(':').append(info.optInt("port", 8787)).append('\n')
            append("\n提示：原生降级界面仅提供只读状态；完整界面需要系统 WebView。")
        }
    }

    private fun rate(status: JSONObject, key: String): String {
        val value = status.optDouble(key, Double.NaN)
        if (value.isNaN() || value <= 0) return "0 B/s"
        return when {
            value < 1_024 -> "${value.toLong()} B/s"
            value < 1_048_576 -> "%.1f KB/s".format(value / 1_024)
            else -> "%.1f MB/s".format(value / 1_048_576)
        }
    }

    private fun percent(status: JSONObject, key: String): String =
        "%.1f%%".format(status.optDouble(key, 0.0))

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

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

    companion object {
        private const val FALLBACK_REFRESH_MS = 2_000L
    }
}

/** Small seam for regression tests and for firmware without a WebView provider. */
internal object WebViewProviderProbe {
    fun isAvailable(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return runCatching { WebView.getCurrentWebViewPackage() != null }.getOrDefault(false)
    }
}
