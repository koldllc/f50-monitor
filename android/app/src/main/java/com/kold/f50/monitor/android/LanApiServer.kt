package com.kold.f50.monitor.android

import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.charset.StandardCharsets
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** Small read-only HTTP server. It deliberately has no write/control endpoint. */
class LanApiServer(private val runtime: RuntimeState) {
    companion object { const val PORT = 8787 }

    @Volatile private var running = false
    private var server: ServerSocket? = null
    private var thread: Thread? = null
    private var clients: ExecutorService? = null

    @Synchronized
    fun start() {
        if (running) return
        running = true
        clients = Executors.newFixedThreadPool(4) { runnable ->
            Thread(runnable, "f50-api-client").apply { isDaemon = true }
        }
        thread = Thread {
            try {
                ServerSocket(PORT, 32, InetAddress.getByName("0.0.0.0")).use { socket ->
                    server = socket
                    while (running) {
                        val client = socket.accept()
                        runCatching { clients?.execute { handle(client) } }
                            .onFailure { runCatching { client.close() } }
                    }
                }
            } catch (_: Exception) {
                // Closing the server during stop() also exits through here.
            } finally {
                running = false
                server = null
                clients?.shutdownNow()
                clients = null
            }
        }.apply { name = "f50-lan-api"; isDaemon = true; start() }
    }

    @Synchronized
    fun stop() {
        running = false
        runCatching { server?.close() }
        server = null
        runCatching { thread?.join(500) }
        thread = null
        clients?.shutdownNow()
        clients = null
    }

    private fun handle(socket: Socket) {
        socket.use { client ->
            client.soTimeout = 3000
            val reader = BufferedReader(InputStreamReader(client.getInputStream(), StandardCharsets.US_ASCII))
            val request = reader.readLine() ?: return
            val headers = mutableMapOf<String, String>()
            while (true) {
                val line = reader.readLine() ?: break
                if (line.isEmpty()) break
                val separator = line.indexOf(':')
                if (separator > 0) headers[line.substring(0, separator).lowercase()] = line.substring(separator + 1).trim()
            }
            val parts = request.split(' ')
            val method = parts.getOrNull(0) ?: ""
            val path = parts.getOrNull(1)?.substringBefore('?') ?: "/"
            val key = headers["x-f50-agent-key"]
            val (status, body) = when {
                method != "GET" -> 405 to "{\"error\":\"只读 API 仅支持 GET\"}"
                path == "/health" -> 200 to "{\"ok\":true,\"service\":\"f50-agent\",\"version\":\"0.1.0\"}"
                !runtime.isAuthorized(key) -> 401 to "{\"error\":\"缺少或无效的 X-F50-Agent-Key\"}"
                path == "/api/v1/status" -> 200 to runtime.statusJson()
                path == "/api/v1/capabilities" -> 200 to runtime.capabilitiesJson()
                else -> 404 to "{\"error\":\"Not Found\"}"
            }
            val writer = OutputStreamWriter(client.getOutputStream(), StandardCharsets.UTF_8)
            writer.write("HTTP/1.1 $status ${reason(status)}\r\n")
            writer.write("Content-Type: application/json; charset=utf-8\r\n")
            writer.write("Cache-Control: no-store\r\n")
            writer.write("Content-Length: ${body.toByteArray(StandardCharsets.UTF_8).size}\r\n")
            writer.write("Connection: close\r\n\r\n")
            writer.write(body)
            writer.flush()
        }
    }

    private fun reason(status: Int): String = when (status) {
        200 -> "OK"; 401 -> "Unauthorized"; 404 -> "Not Found"; 405 -> "Method Not Allowed"; else -> "Error"
    }
}
