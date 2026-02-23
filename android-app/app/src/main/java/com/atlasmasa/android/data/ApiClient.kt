package com.atlasmasa.android.data

import com.atlasmasa.android.domain.HealthCapabilities
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.ConnectionPool
import okhttp3.Dispatcher
import java.io.IOException
import java.util.concurrent.TimeUnit

class ApiClient(
    private val baseUrl: String,
    private val okHttp: OkHttpClient = OkHttpClient.Builder()
        .connectionPool(ConnectionPool(3, 5, TimeUnit.MINUTES))
        .dispatcher(Dispatcher().apply {
            maxRequests = 16
            maxRequestsPerHost = 6
        })
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(12, TimeUnit.SECONDS)
        .writeTimeout(12, TimeUnit.SECONDS)
        .followRedirects(false)
        .followSslRedirects(false)
        .addInterceptor { chain ->
            val request = chain.request()
            val url = request.url
            if (url.scheme != "https" || url.host !in ALLOWED_HOSTS) {
                throw IOException("Blocked insecure or untrusted host: ${url.host}")
            }
            chain.proceed(request)
        }
        .retryOnConnectionFailure(true)
        .build(),
    private val json: Json = Json { ignoreUnknownKeys = true },
) {
    private val normalizedBaseUrl = baseUrl.trim().trimEnd('/')

    init {
        require(isAllowedBaseUrl(normalizedBaseUrl)) {
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

    suspend fun healthCapabilities(): Result<HealthCapabilities> = withContext(Dispatchers.IO) {
        runCatching {
            val req = Request.Builder().url("$normalizedBaseUrl/health").get().build()
            okHttp.newCall(req).execute().use { rsp ->
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

    companion object {
        private val ALLOWED_HOSTS = setOf(
            "api.atlasmasa.com",
            "journeyatlas-production.up.railway.app",
        )

        private fun isAllowedBaseUrl(baseUrl: String): Boolean {
            val parsed = baseUrl.toHttpUrlOrNull() ?: return false
            return parsed.scheme == "https" && parsed.host in ALLOWED_HOSTS
        }
    }
}
