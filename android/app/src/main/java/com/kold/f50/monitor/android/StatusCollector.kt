package com.kold.f50.monitor.android

import android.content.Context
import android.content.SharedPreferences
import android.telephony.CellSignalStrengthLte
import android.telephony.CellSignalStrengthNr
import android.telephony.TelephonyManager
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.NetworkInterface
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest
import org.json.JSONArray
import java.util.concurrent.atomic.AtomicReference

class StatusCollector(
    private val context: Context,
    private val preferences: SharedPreferences
) {
    private val cached = AtomicReference(
        preferences.getString("status_cache", null) ?: defaultStatus().toString()
    )
    private var previousCpu: CpuSample? = null
    private var lastQosAt = 0L
    private var qos: QosResult? = null
    private var sessionCookie: String? = null
    private var routerRetryAt = 0L
    private var previousNetSample: NetSample? = null

    fun currentStatus(): String = cached.get()

    @Synchronized
    fun refresh(config: F50Config) {
        val previous = runCatching { JSONObject(cached.get()) }.getOrDefault(defaultStatus())
        val next = JSONObject(previous.toString())
        val router = routerBase(config.baseURL)
        val now = System.currentTimeMillis()
        val attemptedRouter = now >= routerRetryAt
        var fetch: RouterFetch? = null
        if (attemptedRouter) fetch = fetchRouter(router)
        if (fetch != null && (!fetch.valid || fetch.httpStatus == 401 || fetch.httpStatus == 403)) {
            // One bounded login retry. A failed retry is returned to the cache;
            // this cycle never enters a login loop.
            if (login(router, config.password)) fetch = fetchRouter(router)
        }
        if (attemptedRouter) routerRetryAt = if (fetch?.valid == true) 0L else now + ROUTER_RETRY_MS

        val payload = fetch?.takeIf { it.valid }?.payload
        if (payload != null) {
            parseRouter(next, payload)
            next.put("isOnline", true)
            next.put("errorMessage", JSONObject.NULL)
        } else {
            val localTelemetry = applyLocalTelemetry(next)
            next.put("isOnline", localTelemetry)
            next.put("errorMessage", if (localTelemetry) JSONObject.NULL else "无法连接 Router $router")
        }

        val metrics = ProcMetrics.read(previousCpu)
        previousCpu = metrics.cpuSample
        if (metrics.cpuUsage != null) next.put("cpuUsage", metrics.cpuUsage)
        if (metrics.memUsage != null) next.put("memUsage", metrics.memUsage)
        if (metrics.temperature != null) next.put("temperature", metrics.temperature)

        if (now - lastQosAt > 30_000) {
            qos = BinderQosProbe.query()
            lastQosAt = now
        }
        qos?.let {
            next.put("qci", it.qci)
            next.put("qosDl", it.downlink)
            next.put("qosUl", it.uplink)
        }

        val serialized = next.toString()
        cached.set(serialized)
        preferences.edit().putString("status_cache", serialized).apply()
    }

    fun capabilities(): String {
        val thermal = File("/sys/class/thermal").isDirectory
        return JSONObject().apply {
            put("apiVersion", "v1")
            put("readOnly", true)
            put("localTypedControls", true)
            put("lanApi", true)
            put("sms", false)
            put("localSMS", true)
            put("scrcpy", false)
            put("routerGoform", true)
            put("procMetrics", true)
            put("thermalMetrics", thermal)
            put("binderQos", true)
            put("statusCache", true)
        }.toString()
    }

    fun lanHost(): String = runCatching {
        val interfaces = NetworkInterface.getNetworkInterfaces() ?: return@runCatching ""
        interfaces.asSequence().toList()
            .flatMap { it.inetAddresses.asSequence().toList() }
            .filterIsInstance<Inet4Address>()
            .firstOrNull { !it.isLoopbackAddress && !it.isLinkLocalAddress && it.isSiteLocalAddress }
            ?.hostAddress
            .orEmpty()
    }.getOrDefault("")

    private fun fetchRouter(base: String): RouterFetch? {
        val commands = listOf(
            "network_type", "network_provider", "signalbar", "network_signalbar",
            "lte_rsrp", "lte_rsrq", "lte_snr", "5g_rsrp", "5g_rsrq", "5g_snr",
            "Nr_bands", "nr5g_action_band", "battery_value", "battery_charging",
            "wifi_access_sta_num", "realtime_rx_thrpt", "realtime_tx_thrpt",
            "monthly_rx_bytes", "monthly_tx_bytes", "day_rx_bytes", "day_tx_bytes",
            "data_volume_limit_size", "data_volume_clear_date", "traffic_clear_date",
            "ppp_status", "qci", "dl_ambr", "ul_ambr", "cpu_utility", "mem_utility",
            "temperature", "cpu_temp", "internal_temperature", "ic_temp"
        ).joinToString(",")
        val query = "multi_data=1&isTest=false&cmd=" + URLEncoder.encode(commands, "UTF-8")
        var connection: HttpURLConnection? = null
        return try {
            connection = (URL("$base/goform/goform_get_cmd_process?$query").openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 2500
                readTimeout = 2500
                setRequestProperty("Referer", "$base/index.html")
                sessionCookie?.let { setRequestProperty("Cookie", it) }
            }
            val status = connection.responseCode
            if (status !in 200..299) return RouterFetch(status, null, false)
            val payload = connection.inputStream.bufferedReader().use { JSONObject(it.readText()) }
            RouterFetch(status, payload, isValidPayload(payload))
        } catch (_: Exception) {
            null
        } finally {
            connection?.disconnect()
        }
    }

    private fun isValidPayload(payload: JSONObject): Boolean {
        val error = payload.optString("Error", payload.optString("error", "")).trim()
        if (error.isNotEmpty()) return false
        return listOf("network_type", "network_provider", "signalbar", "network_signalbar", "realtime_rx_thrpt", "realtime_tx_thrpt")
            .any { payload.optString(it, "").trim().isNotEmpty() }
    }

    private fun login(base: String, password: String): Boolean {
        if (password.isBlank()) return false
        var ldConnection: HttpURLConnection? = null
        val ld = try {
            val url = "$base/goform/goform_get_cmd_process?isTest=false&cmd=LD&_=${System.currentTimeMillis()}"
            ldConnection = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 2500
                readTimeout = 2500
                setRequestProperty("Referer", "$base/index.html")
                sessionCookie?.let { setRequestProperty("Cookie", it) }
            }
            if (ldConnection.responseCode !in 200..299) ""
            else ldConnection.inputStream.bufferedReader().use { JSONObject(it.readText()).optString("LD", "") }
        } catch (_: Exception) {
            ""
        } finally {
            ldConnection?.disconnect()
        }
        if (ld.isBlank()) return false

        val firstHash = sha256(password)
        val finalHash = sha256(firstHash + ld).uppercase()
        var loginConnection: HttpURLConnection? = null
        return try {
            loginConnection = (URL("$base/goform/goform_set_cmd_process").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                connectTimeout = 2500
                readTimeout = 2500
                setRequestProperty("Referer", "$base/index.html")
                setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                outputStream.use { it.write("goformId=LOGIN&isTest=false&user=admin&password=$finalHash".toByteArray()) }
            }
            val responseCookie = loginConnection.headerFields["Set-Cookie"]?.firstOrNull()
                ?: loginConnection.headerFields["set-cookie"]?.firstOrNull()
            if (!responseCookie.isNullOrBlank()) sessionCookie = responseCookie.substringBefore(';')
            val responseBody = runCatching { loginConnection.inputStream.bufferedReader().use { JSONObject(it.readText()) } }.getOrNull()
            val result = responseBody?.optInt("result", -1) ?: -1
            loginConnection.responseCode in 200..299 && (!responseCookie.isNullOrBlank() || result == 0 || result == 3)
        } catch (_: Exception) {
            false
        } finally {
            loginConnection?.disconnect()
        }
    }

    private fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray())
        .joinToString("") { "%02x".format(it) }

    private fun parseRouter(status: JSONObject, payload: JSONObject) {
        fun text(vararg keys: String): String? = keys.asSequence()
            .map { payload.optString(it, "").trim() }
            .firstOrNull { it.isNotEmpty() }

        text("network_type")?.let { status.put("networkType", it) }
        text("network_provider")?.let { status.put("carrier", it) }
        text("ppp_status")?.let { status.put("pppStatus", it) }
        text("Nr_bands", "nr5g_action_band")?.let { status.put("currentBands", it) }
        text("lte_rsrp", "5g_rsrp")?.let { status.put("rsrp", normalizeUnit(it, "dBm")) }
        text("lte_rsrq", "5g_rsrq")?.let { status.put("rsrq", normalizeUnit(it, "dB")) }
        text("lte_snr", "5g_snr")?.let { status.put("snr", normalizeUnit(it, "dB")) }
        text("qci")?.let { status.put("qci", it) }
        text("dl_ambr")?.let { status.put("qosDl", it) }
        text("ul_ambr")?.let { status.put("qosUl", it) }

        val bars = number(payload, "signalbar", "network_signalbar")
        if (bars != null) status.put("signalBar", bars.toInt().coerceIn(0, 5))
        number(payload, "realtime_rx_thrpt")?.let {
            status.put("dlSpeed", it)
            appendHistory(status, "dlHistory", it)
        }
        number(payload, "realtime_tx_thrpt")?.let {
            status.put("ulSpeed", it)
            appendHistory(status, "ulHistory", it)
        }
        number(payload, "wifi_access_sta_num")?.let { status.put("connectedDevices", it.toInt()) }
        number(payload, "battery_value")?.let { status.put("batteryValue", it.toInt()) }
        number(payload, "battery_charging")?.let { status.put("isCharging", it > 0) }
        number(payload, "monthly_rx_bytes")?.let { status.put("monthlyRx", it.toLong()) }
        number(payload, "monthly_tx_bytes")?.let { status.put("monthlyTx", it.toLong()) }
        number(payload, "day_rx_bytes")?.let { status.put("dailyRx", it.toLong()) }
        number(payload, "day_tx_bytes")?.let { status.put("dailyTx", it.toLong()) }
        number(payload, "data_volume_limit_size")?.let { status.put("trafficLimit", it.toLong()) }
        val rx = status.optLong("packageRx", status.optLong("monthlyRx"))
        val tx = status.optLong("packageTx", status.optLong("monthlyTx"))
        status.put("packageRx", rx)
        status.put("packageTx", tx)
        status.put("packageTotal", rx + tx)
        status.put("ufiDailyUsage", status.optLong("dailyRx"))
        status.put("ufiMonthlyUsage", status.optLong("monthlyRx") + status.optLong("monthlyTx"))
        text("data_volume_clear_date", "traffic_clear_date")?.let { status.put("trafficResetDay", parseResetDay(it)) }
        text("cpu_utility")?.toDoubleOrNull()?.let { status.put("cpuUsage", it) }
        text("mem_utility")?.toDoubleOrNull()?.let { status.put("memUsage", it) }
        text("temperature", "cpu_temp", "internal_temperature", "ic_temp")?.let { value ->
            numberString(value)?.let { status.put("temperature", if (it > 100) it / 1000.0 else it) }
        }
    }

    /** Uses only basic phone state and /proc counters; no identity, location, or SMS access. */
    private fun applyLocalTelemetry(status: JSONObject): Boolean {
        val phone = runCatching { context.getSystemService(TelephonyManager::class.java) }.getOrNull()
        val networkType = phone?.let {
            runCatching { it.dataNetworkType }.getOrDefault(TelephonyManager.NETWORK_TYPE_UNKNOWN)
        } ?: TelephonyManager.NETWORK_TYPE_UNKNOWN
        val connected = phone?.let {
            runCatching { it.dataState == TelephonyManager.DATA_CONNECTED }.getOrDefault(false)
        } ?: false
        var hasCarrier = false
        if (phone != null) {
            runCatching { phone.networkOperatorName.trim() }.getOrNull()?.takeIf { it.isNotEmpty() }?.let {
                hasCarrier = true
                status.put("carrier", it)
            }
            status.put("networkType", networkTypeName(networkType))
            status.put("pppStatus", if (connected) "已连接" else "未连接")
            val signal = runCatching { phone.signalStrength }.getOrNull()
            signal?.let {
                status.put("signalBar", ((it.level.coerceIn(0, 4) * 5) + 2) / 4)
                val cell = it.cellSignalStrengths.firstOrNull { strength ->
                    strength is CellSignalStrengthNr || strength is CellSignalStrengthLte
                }
                when (cell) {
                    is CellSignalStrengthNr -> {
                        putAvailable(status, "rsrp", cell.ssRsrp, "dBm")
                        putAvailable(status, "rsrq", cell.ssRsrq, "dB")
                        putAvailable(status, "snr", cell.ssSinr, "dB")
                    }
                    is CellSignalStrengthLte -> {
                        putAvailable(status, "rsrp", cell.rsrp, "dBm")
                        putAvailable(status, "rsrq", cell.rsrq, "dB")
                        if (cell.rssnr != Int.MAX_VALUE && cell.rssnr != Int.MIN_VALUE) {
                            status.put("snr", "${cell.rssnr / 10.0} dB")
                        }
                    }
                }
            }
        }

        val sample = readNetSample()
        val previous = previousNetSample
        previousNetSample = sample
        if (sample != null && previous != null) {
            val elapsedSeconds = (sample.at - previous.at) / 1000.0
            if (elapsedSeconds > 0) {
                val down = ((sample.rx - previous.rx).coerceAtLeast(0L) / elapsedSeconds)
                val up = ((sample.tx - previous.tx).coerceAtLeast(0L) / elapsedSeconds)
                status.put("dlSpeed", down)
                status.put("ulSpeed", up)
                appendHistory(status, "dlHistory", down)
                appendHistory(status, "ulHistory", up)
            }
        }
        return networkType != TelephonyManager.NETWORK_TYPE_UNKNOWN && (connected || hasCarrier)
    }

    private fun putAvailable(status: JSONObject, key: String, value: Int, unit: String) {
        if (value != Int.MAX_VALUE && value != Int.MIN_VALUE && value < 1_000_000) {
            status.put(key, "$value $unit")
        }
    }

    private fun readNetSample(): NetSample? = runCatching {
        val line = File("/proc/net/dev").readLines().firstOrNull { it.trimStart().startsWith("sipa_eth0:") }
            ?: return@runCatching null
        val fields = line.substringAfter(':').trim().split(Regex("\\s+"))
        if (fields.size < 9) return@runCatching null
        NetSample(fields[0].toLongOrNull() ?: return@runCatching null, fields[8].toLongOrNull() ?: return@runCatching null, System.currentTimeMillis())
    }.getOrNull()

    internal fun networkTypeName(type: Int): String = when (type) {
        TelephonyManager.NETWORK_TYPE_NR -> "5G NR"
        TelephonyManager.NETWORK_TYPE_LTE -> "4G LTE"
        TelephonyManager.NETWORK_TYPE_UMTS -> "3G UMTS"
        TelephonyManager.NETWORK_TYPE_HSDPA, TelephonyManager.NETWORK_TYPE_HSUPA,
        TelephonyManager.NETWORK_TYPE_HSPA, TelephonyManager.NETWORK_TYPE_HSPAP -> "3G"
        TelephonyManager.NETWORK_TYPE_EDGE, TelephonyManager.NETWORK_TYPE_GPRS -> "2G"
        else -> "未知"
    }

    private fun number(payload: JSONObject, vararg keys: String): Double? = keys.asSequence()
        .mapNotNull { payload.optString(it, "").trim().toDoubleOrNull() }
        .firstOrNull()

    private fun numberString(value: String): Double? = value.trim().toDoubleOrNull()

    private fun appendHistory(status: JSONObject, key: String, value: Double) {
        val values = (status.optJSONArray(key)?.let { array ->
            (0 until array.length()).mapNotNull { index -> array.optDouble(index).takeUnless { it.isNaN() } }
        } ?: emptyList()).toMutableList()
        values.add(value)
        status.put(key, JSONArray().apply { values.takeLast(16).forEach { put(it) } })
    }

    private fun parseResetDay(value: String): Int = Regex("\\d+").findAll(value)
        .mapNotNull { it.value.toIntOrNull() }
        .filter { it in 1..31 }
        .lastOrNull() ?: 0

    private fun normalizeUnit(value: String, unit: String): String =
        if (value.contains("dB", true) || value.contains("dBm", true)) value else "$value $unit"

    private fun routerBase(baseURL: String): String {
        val clean = RouterEndpoint.normalize(baseURL)
        return if (clean.endsWith(":2333")) clean.removeSuffix(":2333") else clean
    }

    private fun defaultStatus(): JSONObject = JSONObject().apply {
        put("isOnline", false); put("errorMessage", "尚未采集")
        put("networkType", "5G SA"); put("signalBar", 0); put("rsrp", "N/A"); put("rsrq", "N/A"); put("snr", "N/A")
        put("carrier", "未知"); put("currentBands", ""); put("pppStatus", "未连接")
        put("qci", ""); put("qosDl", ""); put("qosUl", "")
        put("dlSpeed", 0.0); put("ulSpeed", 0.0); put("dlHistory", JSONArray()); put("ulHistory", JSONArray())
        put("connectedDevices", 0); put("smsUnreadCount", 0); put("cpuUsage", 0.0); put("memUsage", 0.0); put("temperature", 0.0)
        put("batteryValue", -1); put("isCharging", false)
        listOf("monthlyRx", "monthlyTx", "dailyRx", "dailyTx", "packageRx", "packageTx", "packageTotal", "ufiDailyUsage", "ufiMonthlyUsage", "trafficLimit").forEach { put(it, 0) }
        put("trafficResetDay", 0); put("daysUntilReset", JSONObject.NULL)
    }

    companion object {
        private const val ROUTER_RETRY_MS = 30_000L
    }
}

private data class NetSample(val rx: Long, val tx: Long, val at: Long)

private data class RouterFetch(val httpStatus: Int, val payload: JSONObject?, val valid: Boolean)

data class CpuSample(val total: Long, val idle: Long)
data class ProcMetrics(val cpuUsage: Double?, val memUsage: Double?, val temperature: Double?, val cpuSample: CpuSample?) {
    companion object {
        fun read(previous: CpuSample?): ProcMetrics {
            val stat = runCatching { File("/proc/stat").readLines().firstOrNull { it.startsWith("cpu ") } }.getOrNull()
            val sample = stat?.trim()?.split(Regex("\\s+"))?.drop(1)?.mapNotNull { it.toLongOrNull() }?.let { values ->
                if (values.size >= 4) CpuSample(values.sum(), values[3]) else null
            }
            val usage = if (sample != null && previous != null && sample.total > previous.total) {
                ((sample.total - previous.total - (sample.idle - previous.idle)).toDouble() / (sample.total - previous.total) * 100).coerceIn(0.0, 100.0)
            } else null
            val mem = runCatching {
                val values = File("/proc/meminfo").readLines().associate { line ->
                    val parts = line.split(Regex(":\\s+"), limit = 2)
                    parts[0] to parts.getOrNull(1)?.trim()?.split(Regex("\\s+"))?.firstOrNull()?.toLongOrNull()
                }
                val total = values["MemTotal"] ?: 0
                val available = values["MemAvailable"] ?: values["MemFree"] ?: total
                if (total > 0) ((total - available).toDouble() / total * 100).coerceIn(0.0, 100.0) else null
            }.getOrNull()
            val temp = File("/sys/class/thermal").listFiles()?.asSequence()?.mapNotNull { zone ->
                runCatching { zone.resolve("temp").takeIf(File::exists)?.readText()?.trim()?.toDoubleOrNull() }.getOrNull()
            }?.map { if (it > 100) it / 1000.0 else it }?.filter { it in -20.0..150.0 }?.maxOrNull()
            return ProcMetrics(usage, mem, temp, sample)
        }
    }
}

data class QosResult(val qci: String, val downlink: String, val uplink: String)

object BinderQosProbe {
    fun query(): QosResult? {
        return runCatching {
            val command = if (android.os.Build.VERSION.SDK_INT > 33) {
                "service call vendor.sprd.hardware.tool.IToolControl/default 3 i32 0 s16 'AT+CGEQOSRDP=1'"
            } else {
                "service call vendor.sprd.hardware.log.ILogControl/default 1 s16 'miscserver' s16 'sendAt 0 AT+CGEQOSRDP=1'"
            }
            val process = Runtime.getRuntime().exec(arrayOf("sh", "-c", command))
            if (!process.waitFor(2, java.util.concurrent.TimeUnit.SECONDS)) {
                process.destroy()
                return null
            }
            val output = process.inputStream.bufferedReader().use { it.readText() }
            val decoded = decodeBinderParcel(output)
            val response = Regex("\\+CGEQOSRDP:\\s*([^\\r\\n]+)").find(decoded)?.groupValues?.get(1) ?: return null
            val fields = response.split(',').map { it.trim() }
            if (fields.size < 8) return null
            val downlink = fields[6].toLongOrNull() ?: return null
            val uplink = fields[7].toLongOrNull() ?: return null
            QosResult(fields[1], formatKbps(downlink), formatKbps(uplink))
        }.getOrNull()
    }

    private fun decodeBinderParcel(output: String): String {
        val decoded = StringBuilder()
        var skippedHeaderWords = 0
        output.lineSequence().forEach { line ->
            line.substringBefore("'").split(Regex("[\\s:]+"))
                .filter { it.length == 8 && it.all { char -> char in '0'..'9' || char.lowercaseChar() in 'a'..'f' } }
                .forEach { word ->
                    if (skippedHeaderWords < 2) {
                        skippedHeaderWords++
                        return@forEach
                    }
                    val bytes = (6 downTo 0 step 2).map { offset -> word.substring(offset, offset + 2).toInt(16) }
                    for (index in 0 until 4 step 2) {
                        val scalar = bytes[index] or (bytes[index + 1] shl 8)
                        if (scalar >= 32 || scalar == 10 || scalar == 13) decoded.append(scalar.toChar())
                    }
                }
        }
        return decoded.toString().trim()
    }

    private fun formatKbps(kbps: Long): String = if (kbps >= 1000) "${kbps / 1000} Mbps" else "$kbps Kbps"
}
