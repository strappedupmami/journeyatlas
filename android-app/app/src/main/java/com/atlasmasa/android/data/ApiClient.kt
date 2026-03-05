package com.atlasmasa.android.data

import com.atlasmasa.android.BuildConfig
import com.atlasmasa.android.domain.HealthCapabilities
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.ConnectionPool
import okhttp3.Dispatcher
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.JavaNetCookieJar
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.net.CookieManager
import java.util.Locale
import java.util.concurrent.TimeUnit

class ApiClient(
    private val baseUrl: String,
    private val okHttp: OkHttpClient = buildDefaultClient(),
    private val json: Json = Json { ignoreUnknownKeys = true },
) {
    private val allowDebugHosts = BuildConfig.DEBUG
    private val normalizedBaseUrl = sanitizeBaseUrl(baseUrl, allowDebugHosts)
    private val parsedBaseUrl = normalizedBaseUrl.toHttpUrlOrNull()
        ?: throw IllegalArgumentException("API base URL is invalid.")

    val resolvedBaseUrl: String
        get() = normalizedBaseUrl

    val resolvedHost: String
        get() = parsedBaseUrl.host

    init {
        require(isAllowedBaseUrl(normalizedBaseUrl, allowDebugHosts)) {
            "API base URL must be HTTPS and on an approved Atlas host."
        }
    }

    @Serializable
    private data class HealthWire(
        val status: String,
        @SerialName("capabilities") val capabilities: CapabilitiesWire,
    )

    @Serializable
    private data class CapabilitiesWire(
        @SerialName("google_oauth") val googleOAuth: Boolean = false,
        @SerialName("apple_oauth") val appleOAuth: Boolean = false,
        @SerialName("passkey") val passkey: Boolean = true,
        @SerialName("billing") val billing: Boolean = false,
        @SerialName("deep_personalization") val deepPersonalization: Boolean = true,
    )

    @Serializable
    private data class AuthMeWire(
        val user: AuthUserWire,
        val subscription: AuthSubscriptionWire? = null,
    )

    @Serializable
    private data class AuthUserWire(
        val provider: String,
        val name: String? = null,
        val email: String? = null,
    )

    @Serializable
    private data class AuthSubscriptionWire(
        @SerialName("cloud_compute_enabled") val cloudComputeEnabled: Boolean? = null,
        @SerialName("usage_billing_active") val usageBillingActive: Boolean? = null,
    )

    @Serializable
    private data class ChatRequestWire(
        @SerialName("session_id") val sessionID: String? = null,
        val text: String,
        val locale: String? = null,
        @SerialName("user_id") val userID: String? = null,
        @SerialName("preferred_format") val preferredFormat: String? = null,
        @SerialName("response_depth") val responseDepth: String? = null,
        @SerialName("response_tone") val responseTone: String? = null,
        @SerialName("include_proactive") val includeProactive: Boolean? = null,
    )

    @Serializable
    private data class ChatResponseWire(
        @SerialName("reply_text") val replyText: String,
    )

    @Serializable
    private data class SlowLoadWire(
        val kind: String,
        val source: String,
        val url: String,
        val referrer: String,
        @SerialName("userAgent") val userAgent: String,
        val timestamp: String,
        @SerialName("thresholdMs") val thresholdMs: Int,
        val metrics: Map<String, Int>,
        val method: String,
        val error: String? = null,
    )

    data class AuthSessionUser(
        val provider: String,
        val name: String?,
        val email: String?,
        val prepaidCreditsActive: Boolean,
    )

    suspend fun healthCapabilities(): Result<HealthCapabilities> = withContext(Dispatchers.IO) {
        runCatching {
            val req = baseRequest(path = "/health")
                .get()
                .build()
            monitoredExecute(req, path = "/health", method = "GET").use { rsp ->
                if (!rsp.isSuccessful) error("health status ${rsp.code}")
                val body = rsp.body?.string().orEmpty()
                val payload = json.decodeFromString(HealthWire.serializer(), body)
                HealthCapabilities(
                    googleOAuth = payload.capabilities.googleOAuth,
                    appleOAuth = payload.capabilities.appleOAuth,
                    passkey = payload.capabilities.passkey,
                    billing = payload.capabilities.billing,
                    deepPersonalization = payload.capabilities.deepPersonalization,
                )
            }
        }
    }

    suspend fun authMe(): Result<AuthSessionUser> = withContext(Dispatchers.IO) {
        runCatching {
            val req = baseRequest(path = "/v1/auth/me")
                .get()
                .build()
            monitoredExecute(req, path = "/v1/auth/me", method = "GET").use { rsp ->
                if (!rsp.isSuccessful) error("auth status ${rsp.code}")
                val body = rsp.body?.string().orEmpty()
                val payload = json.decodeFromString(AuthMeWire.serializer(), body)
                val prepaidCreditsActive = payload.subscription?.usageBillingActive
                    ?: payload.subscription?.cloudComputeEnabled
                    ?: false
                AuthSessionUser(
                    provider = payload.user.provider,
                    name = payload.user.name,
                    email = payload.user.email,
                    prepaidCreditsActive = prepaidCreditsActive,
                )
            }
        }
    }

    suspend fun logout(): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val req = baseRequest(path = "/v1/auth/logout")
                .post("{}".toRequestBody(JSON_MEDIA))
                .build()
            monitoredExecute(req, path = "/v1/auth/logout", method = "POST").use { rsp ->
                if (!rsp.isSuccessful) error("logout status ${rsp.code}")
                Unit
            }
        }
    }

    suspend fun chatReply(
        text: String,
        locale: String?,
    ): Result<String> = withContext(Dispatchers.IO) {
        runCatching {
            val payload = ChatRequestWire(
                text = text.trim(),
                locale = locale?.trim()?.ifEmpty { null },
            )
            val req = baseRequest(path = "/v1/chat")
                .post(json.encodeToString(payload).toRequestBody(JSON_MEDIA))
                .build()
            monitoredExecute(req, path = "/v1/chat", method = "POST").use { rsp ->
                if (!rsp.isSuccessful) error("chat status ${rsp.code}")
                val body = rsp.body?.string().orEmpty()
                val parsed = json.decodeFromString(ChatResponseWire.serializer(), body)
                val clean = parsed.replyText.trim()
                if (clean.isEmpty()) {
                    error("chat returned empty reply_text")
                }
                clean
            }
        }
    }

    private fun monitoredExecute(request: Request, path: String, method: String): Response {
        val startedAtNanos = System.nanoTime()
        return try {
            val response = okHttp.newCall(request).execute()
            reportSlowCallIfNeeded(
                path = path,
                method = method,
                durationMs = elapsedMillisSince(startedAtNanos),
                statusCode = response.code,
                errorMessage = null,
            )
            response
        } catch (error: Exception) {
            reportSlowCallIfNeeded(
                path = path,
                method = method,
                durationMs = elapsedMillisSince(startedAtNanos),
                statusCode = null,
                errorMessage = error.message ?: error::class.java.simpleName,
            )
            throw error
        }
    }

    private fun elapsedMillisSince(startedAtNanos: Long): Int {
        val elapsed = (System.nanoTime() - startedAtNanos) / 1_000_000L
        return elapsed.coerceAtLeast(0L).coerceAtMost(120_000L).toInt()
    }

    private fun reportSlowCallIfNeeded(
        path: String,
        method: String,
        durationMs: Int,
        statusCode: Int?,
        errorMessage: String?,
    ) {
        if (durationMs < SLOW_LOAD_THRESHOLD_MS) {
            return
        }
        val endpoint = slowLoadEndpoint() ?: return
        val payload = SlowLoadWire(
            kind = "network-request",
            source = "android-app",
            url = "$normalizedBaseUrl${path.trim()}".take(MAX_SLOW_LOAD_TEXT),
            referrer = "",
            userAgent = (System.getProperty("http.agent") ?: "AtlasMasaAndroid/1.0").take(MAX_SLOW_LOAD_TEXT),
            timestamp = System.currentTimeMillis().toString(),
            thresholdMs = SLOW_LOAD_THRESHOLD_MS,
            metrics = mapOf(
                "requestDurationMs" to durationMs,
                "httpStatus" to (statusCode ?: -1),
            ),
            method = method,
            error = errorMessage?.take(MAX_SLOW_LOAD_TEXT),
        )
        val request = Request.Builder()
            .url(endpoint)
            .header("Content-Type", "application/json")
            .post(json.encodeToString(payload).toRequestBody(JSON_MEDIA))
            .build()
        okHttp.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                // Silent failure by design.
            }

            override fun onResponse(call: Call, response: Response) {
                response.close()
            }
        })
    }

    private fun slowLoadEndpoint(): HttpUrl? {
        val host = parsedBaseUrl.host.lowercase(Locale.US)
        val scheme = parsedBaseUrl.scheme.lowercase(Locale.US)
        return if (host == "localhost" || host == "127.0.0.1") {
            "$scheme://$host:3000/api/ops/slow-load".toHttpUrlOrNull()
        } else {
            "https://atlasmasa.com/api/ops/slow-load".toHttpUrlOrNull()
        }
    }

    private fun baseRequest(path: String): Request.Builder {
        val url = absoluteUrl(path)
        return Request.Builder()
            .url(url)
            .header("Accept", "application/json")
            .header("Cache-Control", "no-store")
            .header("X-Client", "AtlasMasaAndroid/1.0")
            .header("Origin", originHeaderValue())
    }

    private fun absoluteUrl(path: String): HttpUrl {
        val trimmedPath = path.trim()
        require(trimmedPath.startsWith("/")) {
            "API path must start with /"
        }
        require(!trimmedPath.contains("://") && !trimmedPath.startsWith("//")) {
            "Blocked unsafe API path."
        }
        val built = "$normalizedBaseUrl$trimmedPath".toHttpUrlOrNull()
            ?: throw IOException("Invalid API URL")
        if (!built.host.equals(parsedBaseUrl.host, ignoreCase = true)) {
            throw IOException("Blocked host mismatch in API path.")
        }
        if (!isAllowedHttpUrl(built, allowDebugHosts)) {
            throw IOException("Blocked insecure or untrusted host: ${built.host}")
        }
        return built
    }

    private fun originHeaderValue(): String {
        val host = parsedBaseUrl.host.lowercase()
        if (host == "localhost" || host == "127.0.0.1") {
            val port = when (parsedBaseUrl.port) {
                80, 443 -> 5500
                else -> parsedBaseUrl.port
            }
            return "${parsedBaseUrl.scheme}://$host:$port"
        }
        return "https://atlasmasa.com"
    }

    companion object {
        private const val DEFAULT_API_BASE_URL = "https://api.atlasmasa.com"
        private val PRODUCTION_HOSTS = setOf(
            "api.atlasmasa.com",
            "journeyatlas-production.up.railway.app",
        )
        private val LOCAL_DEBUG_HOSTS = setOf("localhost", "127.0.0.1")
        private val JSON_MEDIA = "application/json".toMediaType()
        private const val SLOW_LOAD_THRESHOLD_MS = 4500
        private const val MAX_SLOW_LOAD_TEXT = 300

        fun defaultApiBaseUrl(): String = DEFAULT_API_BASE_URL

        fun sanitizeBaseUrl(
            rawValue: String?,
            allowDebugHosts: Boolean = BuildConfig.DEBUG,
        ): String {
            val cleaned = rawValue?.trim().orEmpty()
            if (cleaned.isEmpty()) {
                return DEFAULT_API_BASE_URL
            }
            val parsed = cleaned.trimEnd('/').toHttpUrlOrNull() ?: return DEFAULT_API_BASE_URL
            val normalized = parsed.toString().trimEnd('/')
            return if (isAllowedBaseUrl(normalized, allowDebugHosts)) {
                normalized
            } else {
                DEFAULT_API_BASE_URL
            }
        }

        private fun isAllowedBaseUrl(baseUrl: String, allowDebugHosts: Boolean): Boolean {
            val parsed = baseUrl.toHttpUrlOrNull() ?: return false
            return isAllowedHttpUrl(parsed, allowDebugHosts)
        }

        private fun isAllowedHttpUrl(url: HttpUrl, allowDebugHosts: Boolean): Boolean {
            val scheme = url.scheme.lowercase()
            val host = url.host.lowercase()
            return when (scheme) {
                "https" -> allowDebugHosts || host in PRODUCTION_HOSTS
                "http" -> allowDebugHosts && host in LOCAL_DEBUG_HOSTS
                else -> false
            }
        }

        private fun buildDefaultClient(): OkHttpClient {
            val cookieManager = CookieManager()
            return OkHttpClient.Builder()
                .connectionPool(ConnectionPool(3, 5, TimeUnit.MINUTES))
                .dispatcher(Dispatcher().apply {
                    maxRequests = 16
                    maxRequestsPerHost = 6
                })
                .cookieJar(JavaNetCookieJar(cookieManager))
                .connectTimeout(12, TimeUnit.SECONDS)
                .readTimeout(12, TimeUnit.SECONDS)
                .writeTimeout(12, TimeUnit.SECONDS)
                .followRedirects(false)
                .followSslRedirects(false)
                .retryOnConnectionFailure(true)
                .build()
        }
    }
}
