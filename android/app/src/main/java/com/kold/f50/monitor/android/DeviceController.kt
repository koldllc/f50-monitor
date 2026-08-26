package com.kold.f50.monitor.android

import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** Typed, local-only device controls used by the in-app WebView bridge. */
class DeviceController {
    private var cookie: String? = null
    private var useUfiProxy = false
    private var ufiAuthorization = ""

    @Synchronized
    fun snapshot(config: F50Config): JSONObject {
        val payload = get(config, CONTROL_FIELDS)
        val accessPoints = runCatching { get(config, "queryAccessPointInfo").optJSONArray("ResponseList") }.getOrNull()
        val wifiModule = runCatching { get(config, "queryWiFiModuleSwitch") }.getOrNull()
        val clients = JSONArray()
        appendClients(clients, payload.optJSONArray("station_list"), false, false)
        appendClients(clients, payload.optJSONArray("lan_station_list"), true, false)
        val blockedMacs = payload.optString("BlackMacList").split(';').filter { it.isNotBlank() }
        val blockedNames = payload.optString("BlackNameList").split(';')
        for (index in clients.length() - 1 downTo 0) {
            val mac = clients.optJSONObject(index)?.optString("macAddress").orEmpty()
            if (blockedMacs.any { it.equals(mac, true) }) clients.remove(index)
        }
        blockedMacs.forEachIndexed { index, mac ->
            clients.put(JSONObject().apply {
                put("name", blockedNames.getOrNull(index).orEmpty())
                put("ipAddress", "")
                put("macAddress", mac)
                put("isWired", false)
                put("isBlocked", true)
            })
        }
        return JSONObject().apply {
            val ppp = payload.optString("ppp_status").lowercase()
            put("mobileDataEnabled", ppp !in setOf("ppp_disconnected", "disconnected", "disconnect", "0", "off"))
            put("networkMode", payload.optString("net_select", "WL_AND_5G"))
            val wifiSwitch = first(wifiModule ?: payload, "WiFiModuleSwitch", "queryWiFiModuleSwitch")
            val chip24Enabled = (0 until (accessPoints?.length() ?: 0)).asSequence()
                .mapNotNull { accessPoints?.optJSONObject(it) }
                .firstOrNull { it.optInt("ChipIndex") == 0 && it.optInt("AccessPointIndex") == 0 }
                ?.optString("AccessPointSwitchStatus") == "1"
            val chip5Enabled = (0 until (accessPoints?.length() ?: 0)).asSequence()
                .mapNotNull { accessPoints?.optJSONObject(it) }
                .firstOrNull { it.optInt("ChipIndex") == 1 && it.optInt("AccessPointIndex") == 0 }
                ?.optString("AccessPointSwitchStatus") == "1"
            val radioMode = when {
                wifiSwitch.lowercase() in setOf("0", "off", "disabled", "false") -> "0"
                chip5Enabled && !chip24Enabled -> "2"
                chip24Enabled -> "1"
                payload.optString("wifi_onoff_state").lowercase() in setOf("0", "off", "disabled", "false") -> "0"
                payload.optString("wifi_chip2_ssid1_switch_onoff") == "1" &&
                    payload.optString("wifi_chip1_ssid1_switch_onoff") != "1" -> "2"
                else -> "1"
            }
            val preferredChipIndex = if (radioMode == "2") 1 else 0
            val accessPoint = (0 until (accessPoints?.length() ?: 0)).asSequence()
                .mapNotNull { accessPoints?.optJSONObject(it) }
                .firstOrNull { it.optInt("ChipIndex") == preferredChipIndex && it.optInt("AccessPointIndex") == 0 }
                ?: (0 until (accessPoints?.length() ?: 0)).asSequence()
                    .mapNotNull { accessPoints?.optJSONObject(it) }
                    .firstOrNull { it.optInt("AccessPointIndex") == 0 }
            val accessPointPassword = accessPoint?.optString("Password").orEmpty()
            val encodedPassword = accessPointPassword.ifBlank { payload.optString("WPAPSK1_encode") }
            val decodedPassword = encodedPassword.takeIf { it.isNotBlank() }?.let { value ->
                runCatching { String(Base64.decode(value, Base64.DEFAULT), Charsets.UTF_8) }.getOrNull()
                    ?.takeIf { decoded -> '\uFFFD' !in decoded && decoded.none { it.isISOControl() } }
            }
            val wifiPassword = decodedPassword
                ?: accessPointPassword.ifBlank { payload.optString("WPAPSK1") }
            val chipSsidKey = if (radioMode == "2") "wifi_chip2_ssid1_ssid" else "wifi_chip1_ssid1_ssid"
            val chipMaximumKey = if (radioMode == "2") "wifi_chip2_ssid1_max_access_num" else "wifi_chip1_ssid1_max_access_num"
            put("wifi", JSONObject().apply {
                put("radioMode", radioMode)
                put("ssid", accessPoint?.optString("SSID")?.takeIf { it.isNotBlank() } ?: first(payload, "SSID1", chipSsidKey))
                put("broadcastsSSID", (accessPoint?.optString("ApBroadcastDisabled") ?: payload.optString("HideSSID")) != "1")
                put("securityMode", accessPoint?.optString("AuthMode")?.takeIf { it.isNotBlank() } ?: payload.optString("AuthMode", "WPA2PSK"))
                put("password", wifiPassword)
                put("maximumClients", (accessPoint?.optInt("ApMaxStationNumber", -1)?.takeIf { it > 0 }
                    ?: payload.optInt("MAX_Access_num", payload.optInt(chipMaximumKey, 10))).coerceIn(1, 32))
                put("usesEncodedPassword", decodedPassword != null)
                put("noForwarding", accessPoint?.optString("ApIsolate")?.takeIf { it.isNotBlank() }
                    ?: payload.optString("NoForwarding", "0"))
                put("qrCodeDisplaySwitch", payload.optString("qrcode_display_switch", "1"))
            })
            put("lteBands", payload.optString("lte_band_lock"))
            put("nrBands", payload.optString("nr_band_lock"))
            put("clients", clients)
            put("aclMode", payload.optString("AclMode", "2"))
            put("apn", JSONObject().apply {
                put("index", payload.optInt("apn_Current_index", 0))
                put("isAutomatic", payload.optString("apn_mode") != "manual")
                put("profileName", first(payload, "apn_m_profile_name", "profile_name", "profile_name_ui"))
                put("apn", first(payload, "apn_wan_apn", "wan_apn_ui"))
                put("username", first(payload, "apn_ppp_username", "ppp_username_ui"))
                put("password", first(payload, "apn_ppp_passwd", "ppp_passwd_ui"))
                put("authentication", first(payload, "apn_ppp_auth_mode", "ppp_auth_mode_ui").ifBlank { "none" })
                put("pdpType", first(payload, "apn_pdp_type", "pdp_type_ui").ifBlank { "IPv4v6" })
            })
        }
    }

    @Synchronized
    fun setMobileData(config: F50Config, enabled: Boolean) = set(
        config, mapOf("goformId" to if (enabled) "CONNECT_NETWORK" else "DISCONNECT_NETWORK")
    )

    @Synchronized
    fun setNetworkMode(config: F50Config, mode: String) {
        require(mode in NETWORK_MODES) { "不支持的网络模式" }
        set(config, mapOf("goformId" to "SET_BEARER_PREFERENCE", "BearerPreference" to mode))
    }

    @Synchronized
    fun saveWiFi(config: F50Config, wifi: JSONObject) {
        val ssid = wifi.optString("ssid").trim()
        val radioMode = wifi.optString("radioMode", "2")
        val securityMode = wifi.optString("securityMode", "WPA2PSK")
        val password = wifi.optString("password")
        val maximumClients = wifi.optInt("maximumClients", 10)
        require(radioMode in WIFI_RADIO_MODES) { "不支持的 Wi-Fi 工作频段" }
        if (radioMode == "0") {
            set(config, mapOf(
                "goformId" to "switchWiFiModule",
                "SwitchOption" to radioMode
            ))
            return
        }
        val chipEnum = if (radioMode == "2") "chip2" else "chip1"
        val chipIndex = if (radioMode == "2") "1" else "0"
        require(ssid.isNotBlank() && ssid.toByteArray(Charsets.UTF_8).size <= 32) { "网络名称须为 1～32 字节" }
        require(securityMode in WIFI_SECURITY_MODES) { "不支持的 Wi-Fi 安全模式" }
        require(maximumClients in 1..32) { "最大接入数须为 1～32" }
        require(securityMode == "OPEN" || password.toByteArray(Charsets.UTF_8).size in 8..63) {
            "Wi-Fi 密码须为 8～63 个字符"
        }
        val parameters = mutableMapOf(
            "goformId" to "setAccessPointInfo",
            "ChipIndex" to chipIndex,
            "AccessPointIndex" to "0",
            "AccessPointSwitchStatus" to "1",
            "SSID" to ssid,
            "ApMaxStationNumber" to maximumClients.toString(),
            "ApIsolate" to wifi.optString("noForwarding", "0"),
            "AuthMode" to securityMode,
            "ApBroadcastDisabled" to if (wifi.optBoolean("broadcastsSSID", true)) "0" else "1",
            "EncrypType" to if (securityMode == "OPEN") "NONE" else "CCMP"
        )
        if (securityMode != "OPEN") {
            parameters["Password"] = if (wifi.optBoolean("usesEncodedPassword")) {
                Base64.encodeToString(password.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
            } else password
        }
        set(config, parameters)
        set(config, mapOf(
            "goformId" to "switchWiFiChip",
            "ChipEnum" to chipEnum,
            "GuestEnable" to "0"
        ))
    }

    @Synchronized
    fun saveApn(config: F50Config, apn: JSONObject) {
        val profileName = apn.optString("profileName").trim()
        val apnName = apn.optString("apn").trim()
        require(profileName.isNotBlank() && apnName.isNotBlank()) { "请填写配置名称与 APN" }
        val index = apn.optInt("index", 0).coerceAtLeast(0).toString()
        val auth = apn.optString("authentication", "none")
        val pdp = apn.optString("pdpType", "IPv4v6")
        require(auth in setOf("none", "chap", "pap")) { "鉴权方式无效" }
        require(pdp in setOf("IP", "IPv6", "IPv4v6")) { "PDP 类型无效" }
        val parameters = mutableMapOf(
            "goformId" to "APN_PROC_EX", "apn_mode" to "manual", "apn_action" to "save",
            "profile_name" to profileName, "index" to index, "wan_dial" to "*99#", "apn_wan_dial" to "*99#",
            "apn_select" to "manual", "apn_pdp_type" to pdp, "pdp_type" to pdp,
            "apn_pdp_select" to "auto", "pdp_select" to "auto", "apn_pdp_addr" to "", "pdp_addr" to "",
            "apn_wan_apn" to apnName, "wan_apn" to apnName,
            "apn_ppp_auth_mode" to auth, "ppp_auth_mode" to auth,
            "apn_ppp_username" to apn.optString("username"), "ppp_username" to apn.optString("username"),
            "apn_ppp_passwd" to apn.optString("password"), "ppp_passwd" to apn.optString("password")
        )
        if (pdp != "IP") parameters.putAll(mapOf(
            "apn_ipv6_wan_apn" to apnName, "ipv6_wan_apn" to apnName,
                "apn_ipv6_ppp_auth_mode" to auth, "ipv6_ppp_auth_mode" to auth,
                "apn_ipv6_ppp_username" to apn.optString("username"), "ipv6_ppp_username" to apn.optString("username"),
                "apn_ipv6_ppp_passwd" to apn.optString("password"), "ipv6_ppp_passwd" to apn.optString("password")
        ))
        set(config, parameters)
        set(config, mapOf(
            "goformId" to "APN_PROC_EX", "apn_mode" to "manual", "apn_action" to "set_default",
            "set_default_flag" to "1", "apn_pdp_type" to "", "index" to index
        ))
    }

    @Synchronized
    fun useAutomaticApn(config: F50Config) = set(config, mapOf("goformId" to "APN_PROC_EX", "apn_mode" to "auto"))

    @Synchronized
    fun setBands(config: F50Config, lte: String, nr: String, unlock: Boolean) {
        val lteValue = if (unlock) SUPPORTED_LTE else validateBands(lte)
        val nrValue = if (unlock) SUPPORTED_NR else validateBands(nr)
        require(unlock || lteValue.isNotEmpty() || nrValue.isNotEmpty()) { "至少选择一个频段" }
        set(config, mapOf("goformId" to "LTE_BAND_LOCK", "lte_band_lock" to lteValue))
        set(config, mapOf("goformId" to "NR_BAND_LOCK", "nr_band_lock" to nrValue))
    }

    @Synchronized
    fun lockCell(config: F50Config, pci: Int, earfcn: Int, is5G: Boolean) {
        require(pci in 0..1007 && earfcn > 0) { "PCI 或频点无效" }
        set(config, mapOf(
            "goformId" to "CELL_LOCK", "pci" to pci.toString(), "earfcn" to earfcn.toString(),
            "rat" to if (is5G) "16" else "12"
        ))
    }

    @Synchronized
    fun unlockCells(config: F50Config) = set(config, mapOf("goformId" to "UNLOCK_ALL_CELL"))

    @Synchronized
    fun reboot(config: F50Config) = set(config, mapOf("goformId" to "REBOOT_DEVICE"))

    @Synchronized
    fun setClientBlocked(config: F50Config, mac: String, name: String, blocked: Boolean) {
        require(MAC_REGEX.matches(mac)) { "MAC 地址无效" }
        val state = get(config, "queryDeviceAccessControlList")
        val macs = state.optString("BlackMacList").split(';').filter { it.isNotBlank() }.toMutableList()
        val names = state.optString("BlackNameList").split(';').toMutableList()
        val existing = macs.indexOfFirst { it.equals(mac, true) }
        if (existing >= 0) {
            macs.removeAt(existing)
            if (existing < names.size) names.removeAt(existing)
        }
        if (blocked) {
            macs.add(mac)
            names.add(name)
        }
        set(config, mapOf(
            "goformId" to "setDeviceAccessControlList", "AclMode" to "2",
            "WhiteMacList" to "", "WhiteNameList" to "",
            "BlackMacList" to macs.joinToString(";"), "BlackNameList" to names.joinToString(";")
        ))
    }

    @Synchronized
    fun getSmsMessages(config: F50Config): JSONArray {
        val payload = get(config, "sms_data_total", mapOf(
            "page" to "0", "data_per_page" to "500", "mem_store" to "1", "tags" to "100",
            "order_by" to "order by id desc"
        ))
        val rows = payload.optJSONArray("messages") ?: payload.optJSONArray("sms_data")
            ?: payload.optJSONArray("data") ?: JSONArray()
        return JSONArray().apply {
            for (index in 0 until rows.length()) {
                val row = rows.optJSONObject(index) ?: continue
                val content = decodeSms(row.optString("content", row.optString("message")))
                put(JSONObject().apply {
                    put("id", row.optString("id", index.toString()))
                    put("number", row.optString("number", row.optString("phone_number")))
                    put("content", content)
                    put("dateText", row.optString("date", row.optString("time")))
                    put("tag", row.optString("tag"))
                    put("isUnread", row.optString("tag") == "1" || row.optString("read") == "0")
                    put("isOutgoing", row.optString("tag") == "2")
                })
            }
        }
    }

    @Synchronized
    fun sendSms(config: F50Config, number: String, content: String) {
        require(number.isNotBlank() && content.isNotBlank()) { "号码与短信内容不能为空" }
        val encoded = content.toCharArray().joinToString("") { "%04x".format(it.code) }
        set(config, mapOf("goformId" to "SEND_SMS", "Number" to number.trim(), "MessageBody" to encoded))
    }

    private fun get(config: F50Config, commands: String, extras: Map<String, String> = emptyMap()): JSONObject {
        ensureLogin(config)
        val params = linkedMapOf("isTest" to "false", "multi_data" to "1", "cmd" to commands).apply { putAll(extras) }
        val connection = open(config, "/goform/goform_get_cmd_process?${form(params)}", "GET")
        return connection.useJson()
    }

    private fun set(config: F50Config, parameters: Map<String, String>) {
        ensureLogin(config)
        val info = getWithoutLogin(config, "Language,cr_version,wa_inner_version")
        val rd = getWithoutLogin(config, "RD").optString("RD")
        val wa = info.optString("wa_inner_version")
        val cr = info.optString("cr_version")
        check(wa.isNotBlank() && cr.isNotBlank() && rd.isNotBlank()) { "无法获取设备鉴权参数" }
        val body = parameters.toMutableMap().apply {
            put("isTest", "false")
            put("AD", sha256(sha256(wa + cr) + rd))
        }
        val response = open(config, "/goform/goform_set_cmd_process", "POST", form(body)).useJson()
        val result = response.optString("result", response.optString("status")).lowercase()
        check(result in setOf("success", "ok", "true", "0", "3")) {
            response.optString("message", response.optString("error", "设备拒绝了控制请求"))
        }
    }

    private fun ensureLogin(config: F50Config) {
        // 已建立的后端会话优先复用；首次连接或会话失效时，
        // F50 本机先走 UFI 内部端口，避免部分固件阻止回连 LAN 网关。
        if (!cookie.isNullOrBlank() && runCatching { loginCurrentBackend(config) }.isSuccess) return

        val tokens = listOf(config.ufiToken, config.password, "admin")
            .map(String::trim)
            .filter(String::isNotBlank)
            .flatMap { listOf(sha256(it), it) }
            .distinct()
        useUfiProxy = true
        for (token in tokens) {
            ufiAuthorization = token
            cookie = null
            if (runCatching { loginCurrentBackend(config) }.isSuccess) return
        }

        useUfiProxy = false
        ufiAuthorization = ""
        cookie = null
        if (runCatching { loginCurrentBackend(config) }.isSuccess) return

        throw IllegalStateException("无法登录 Router 或 UFI 控制后端")
    }

    private fun loginCurrentBackend(config: F50Config) {
        if (!cookie.isNullOrBlank()) {
            val state = runCatching { getWithoutLogin(config, "loginfo").optString("loginfo") }.getOrNull()
            if (state == "ok") return
            cookie = null
        }
        val ld = getWithoutLogin(config, "LD").optString("LD")
        check(ld.isNotBlank()) { "无法读取 Router 登录参数" }
        val body = form(mapOf(
            "goformId" to "LOGIN", "isTest" to "false", "user" to "admin",
            "password" to sha256(sha256(config.password) + ld).uppercase()
        ))
        val connection = open(config, "/goform/goform_set_cmd_process", "POST", body, includeCookie = false)
        val responseCookie = (connection.getHeaderField("kano-cookie")
            ?: connection.getHeaderField("Set-Cookie"))?.substringBefore(';')
        val response = connection.useJson()
        val result = response.optInt("result", -1)
        check(!responseCookie.isNullOrBlank() || result == 0 || result == 3) { "中兴后台口令验证失败" }
        cookie = responseCookie
    }

    private fun getWithoutLogin(config: F50Config, commands: String): JSONObject {
        val params = form(mapOf("isTest" to "false", "multi_data" to "1", "cmd" to commands, "_" to System.currentTimeMillis().toString()))
        return open(config, "/goform/goform_get_cmd_process?$params", "GET").useJson()
    }

    private fun open(
        config: F50Config,
        path: String,
        method: String,
        body: String? = null,
        includeCookie: Boolean = true
    ): HttpURLConnection {
        val base = if (useUfiProxy) UFI_LOCAL_API else RouterEndpoint.normalize(config.baseURL).trimEnd('/')
        val url = URL(base + path)
        return (url.openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 3_000
            readTimeout = 4_000
            setRequestProperty("Referer", "$base/index.html")
            if (useUfiProxy) {
                val timestamp = System.currentTimeMillis().toString()
                setRequestProperty("authorization", ufiAuthorization)
                setRequestProperty("kano-t", timestamp)
                setRequestProperty("kano-sign", kanoSign("minikano${method.uppercase()}${url.path}$timestamp"))
            }
            if (includeCookie) cookie?.let { setRequestProperty("Cookie", it) }
            if (body != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
                outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            }
        }
    }

    private fun HttpURLConnection.useJson(): JSONObject = try {
        check(responseCode in 200..299) { "Router HTTP $responseCode" }
        inputStream.bufferedReader().use { JSONObject(it.readText()) }
    } finally {
        disconnect()
    }

    private fun form(values: Map<String, String>): String = values.entries.sortedBy { it.key }.joinToString("&") {
        "${URLEncoder.encode(it.key, "UTF-8")}=${URLEncoder.encode(it.value, "UTF-8")}"
    }

    private fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

    private fun kanoSign(value: String): String {
        val hmac = Mac.getInstance("HmacMD5").apply {
            init(SecretKeySpec(KANO_SIGN_KEY.toByteArray(Charsets.UTF_8), "HmacMD5"))
        }.doFinal(value.toByteArray(Charsets.UTF_8))
        val half = hmac.size / 2
        val first = MessageDigest.getInstance("SHA-256").digest(hmac.copyOfRange(0, half))
        val second = MessageDigest.getInstance("SHA-256").digest(hmac.copyOfRange(half, hmac.size))
        return MessageDigest.getInstance("SHA-256").digest(first + second)
            .joinToString("") { "%02x".format(it) }
    }

    private fun appendClients(target: JSONArray, rows: JSONArray?, wired: Boolean, blocked: Boolean) {
        if (rows == null) return
        for (index in 0 until rows.length()) {
            val row = rows.optJSONObject(index) ?: continue
            val mac = first(row, "mac_addr", "mac", "macAddress")
            if (mac.isBlank()) continue
            target.put(JSONObject().apply {
                put("name", first(row, "hostname", "name", "host_name"))
                put("ipAddress", first(row, "ip_addr", "ip", "ipAddress"))
                put("macAddress", mac)
                put("isWired", wired)
                put("isBlocked", blocked)
            })
        }
    }

    private fun first(json: JSONObject, vararg keys: String): String = keys.asSequence()
        .map { json.optString(it).trim() }.firstOrNull { it.isNotEmpty() }.orEmpty()

    private fun validateBands(value: String): String = value.split(',').mapNotNull {
        it.trim().toIntOrNull()?.takeIf { band -> band in 1..1024 }
    }.distinct().sorted().joinToString(",")

    private fun decodeSms(value: String): String = runCatching {
        val decoded = Base64.decode(value, Base64.DEFAULT)
        String(decoded, Charsets.UTF_8).takeIf { it.isNotBlank() } ?: value
    }.getOrDefault(value)

    companion object {
        private val NETWORK_MODES = setOf("WL_AND_5G", "LTE_AND_5G", "Only_5G", "WCDMA_AND_LTE", "Only_LTE", "Only_WCDMA")
        private val WIFI_RADIO_MODES = setOf("0", "1", "2")
        private val WIFI_SECURITY_MODES = setOf("OPEN", "WPA2PSK", "WPAPSKWPA2PSK")
        private val MAC_REGEX = Regex("^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}$")
        private const val SUPPORTED_LTE = "1,3,5,8,34,38,39,40,41"
        private const val SUPPORTED_NR = "1,5,8,28,41,78"
        private const val UFI_LOCAL_API = "http://127.0.0.1:8080/api"
        private const val KANO_SIGN_KEY = "minikano_kOyXz0Ciz4V7wR0IeKmJFYFQ20jd"
        private const val CONTROL_FIELDS = "ppp_status,net_select,queryWiFiModuleSwitch,wifi_onoff_state,wifi_chip1_ssid1_switch_onoff,wifi_chip2_ssid1_switch_onoff,SSID1,wifi_chip1_ssid1_ssid,wifi_chip2_ssid1_ssid,HideSSID,AuthMode,EncrypType,WPAPSK1,WPAPSK1_encode,MAX_Access_num,wifi_chip1_ssid1_max_access_num,wifi_chip2_ssid1_max_access_num,NoForwarding,qrcode_display_switch,lte_band_lock,nr_band_lock,station_list,lan_station_list,queryDeviceAccessControlList,hostNameList,apn_Current_index,apn_mode,apn_m_profile_name,profile_name,profile_name_ui,apn_wan_apn,apn_ppp_username,apn_ppp_passwd,apn_ppp_auth_mode,apn_pdp_type"
    }
}
