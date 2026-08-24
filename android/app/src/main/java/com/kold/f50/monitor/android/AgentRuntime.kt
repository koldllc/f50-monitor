package com.kold.f50.monitor.android

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import org.json.JSONObject
import java.security.SecureRandom
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/** Process-wide runtime shared by the foreground service, WebView bridge and LAN API. */
object AgentRuntime {
    private var runtime: RuntimeState? = null

    @Synchronized
    fun initialize(context: Context): RuntimeState {
        return runtime ?: RuntimeState(context.applicationContext).also { runtime = it }
    }

    fun start(context: Context) = initialize(context).start()

    fun stop() {
        runtime?.stop()
    }

    fun invoke(context: Context, command: String, argsJson: String): String {
        return initialize(context).invoke(command, argsJson)
    }
}

data class F50Config(
    val baseURL: String = "http://127.0.0.1",
    val password: String = "admin",
    val ufiToken: String = "admin",
    val refreshInterval: Double = 2.0,
    val displayMode: String = "图标 + 速率",
    val screenMirroringPort: Int = 5555,
    val launchAtLogin: Boolean = true
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("baseURL", baseURL)
        put("password", password)
        put("ufiToken", ufiToken)
        put("refreshInterval", refreshInterval)
        put("displayMode", displayMode)
        put("screenMirroringPort", screenMirroringPort)
        put("launchAtLogin", launchAtLogin)
    }

    companion object {
        fun fromJson(json: JSONObject, fallback: F50Config): F50Config = F50Config(
            baseURL = json.optString("baseURL", fallback.baseURL),
            password = json.optString("password", fallback.password),
            ufiToken = json.optString("ufiToken", fallback.ufiToken),
            refreshInterval = json.optDouble("refreshInterval", fallback.refreshInterval).coerceIn(1.0, 60.0),
            displayMode = json.optString("displayMode", fallback.displayMode),
            screenMirroringPort = json.optInt("screenMirroringPort", fallback.screenMirroringPort),
            launchAtLogin = json.optBoolean("launchAtLogin", true)
        )
    }
}

class RuntimeState(private val context: Context) {
    private val preferences = context.getSharedPreferences("f50_agent", Context.MODE_PRIVATE)
    private val collector = StatusCollector(preferences)
    private val lanServer = LanApiServer(this)
    private var scheduler: ScheduledExecutorService? = null
    @Volatile private var config = loadConfig()

    val agentKey: String
        get() = synchronized(preferences) {
            preferences.getString("agent_key", null) ?: createAgentKey()
        }

    fun start() {
        if (scheduler != null) return
        agentKey // Persist before headless boot clients access the LAN API.
        lanServer.start()
        scheduler = Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, "f50-status-collector").apply { isDaemon = true }
        }.also { executor ->
            executor.scheduleWithFixedDelay(
                { runCatching { collector.refresh(config) } },
                0,
                config.refreshInterval.toLong().coerceAtLeast(1),
                TimeUnit.SECONDS
            )
        }
    }

    fun stop() {
        scheduler?.shutdownNow()
        scheduler = null
        lanServer.stop()
    }

    fun statusJson(): String = collector.currentStatus()

    fun capabilitiesJson(): String = collector.capabilities()

    fun invoke(command: String, argsJson: String): String {
        return try {
            when (command) {
                "get_status" -> statusJson()
                "get_config" -> config.toJson().toString()
                "get_agent_info" -> agentInfo().toString()
                "request_battery_optimization" -> {
                    requestBatteryOptimization()
                    agentInfo().put("requested", true).toString()
                }
                "save_config" -> {
                    val args = JSONObject(argsJson)
                    val incoming = args.optJSONObject("config") ?: args
                    config = F50Config.fromJson(incoming, config)
                    preferences.edit().putString("config", config.toJson().toString()).apply()
                    // Keep the service's next cycle aligned with the user's choice.
                    restartSchedule()
                    JSONObject().put("success", true).toString()
                }
                "open_url" -> {
                    val url = JSONObject(argsJson).optString("url")
                    if (url.isBlank()) throw IllegalArgumentException("URL 为空")
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    })
                    JSONObject().put("success", true).toString()
                }
                "get_sms_messages", "send_sms" -> unsupported("Android 端不支持短信功能")
                "get_scrcpy_status" -> JSONObject().apply {
                    put("hasAdb", false)
                    put("hasScrcpy", false)
                    put("isInstalled", false)
                    put("isDownloading", false)
                    put("isConnecting", false)
                    put("statusMessage", "Android 端不支持 scrcpy 投屏功能")
                }.toString()
                "download_scrcpy", "launch_scrcpy" -> unsupported("Android 端不支持 scrcpy 投屏功能")
                "submit_feedback" -> unsupported("Android 端暂不支持在线反馈，请通过 GitHub 提交")
                else -> unsupported("Android bridge 不支持操作：$command")
            }
        } catch (error: Exception) {
            JSONObject().put("error", error.message ?: error.javaClass.simpleName).toString()
        }
    }

    private fun unsupported(message: String): String = JSONObject().put("error", message).toString()

    private fun agentInfo(): JSONObject {
        val ignored = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val power = context.getSystemService(PowerManager::class.java)
            power?.isIgnoringBatteryOptimizations(context.packageName) == true
        } else true
        return JSONObject().apply {
            put("host", collector.lanHost())
            put("port", LanApiServer.PORT)
            put("agentKey", agentKey)
            put("batteryOptimizationIgnored", ignored)
        }
    }

    private fun requestBatteryOptimization() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val power = context.getSystemService(PowerManager::class.java)
        if (power?.isIgnoringBatteryOptimizations(context.packageName) == true) return
        context.startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        })
    }

    private fun restartSchedule() {
        if (scheduler == null) return
        scheduler?.shutdownNow()
        scheduler = null
        start()
    }

    private fun loadConfig(): F50Config {
        val raw = preferences.getString("config", null) ?: return F50Config()
        return runCatching { F50Config.fromJson(JSONObject(raw), F50Config()) }.getOrDefault(F50Config())
    }

    private fun createAgentKey(): String {
        val bytes = ByteArray(24)
        SecureRandom().nextBytes(bytes)
        val key = bytes.joinToString("") { "%02x".format(it) }
        preferences.edit().putString("agent_key", key).apply()
        return key
    }

    fun isAuthorized(candidate: String?): Boolean = candidate != null && MessageDigest.isEqual(
        candidate.toByteArray(Charsets.UTF_8), agentKey.toByteArray(Charsets.UTF_8)
    )
}
