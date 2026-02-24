package com.atlasmasa.android.data

import com.atlasmasa.android.domain.LocalReasoningEngine
import com.atlasmasa.android.domain.UserNote
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

class OnDeviceLlmClient(
    private val endpoint: String,
    private val model: String,
    private val enabled: Boolean,
    private val okHttp: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(20, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build(),
    private val json: Json = Json { ignoreUnknownKeys = true },
) {
    @Serializable
    private data class ChatMessage(
        val role: String,
        val content: String,
    )

    @Serializable
    private data class ChatRequest(
        val model: String,
        val messages: List<ChatMessage>,
        val temperature: Double,
        val max_tokens: Int,
        val stream: Boolean = false,
    )

    @Serializable
    private data class ChatResponse(
        val choices: List<Choice> = emptyList(),
    ) {
        @Serializable
        data class Choice(
            val message: Message? = null,
            val text: String? = null,
        )

        @Serializable
        data class Message(
            val role: String? = null,
            val content: String? = null,
        )
    }

    fun isEnabled(): Boolean = enabled

    fun statusLine(): String {
        if (!enabled) {
            return "Local LLM bridge disabled (`LOCAL_LLM_ENABLED=false`)."
        }
        val parsed = endpoint.toHttpUrlOrNull()
        if (parsed == null) {
            return "Local LLM bridge misconfigured (invalid endpoint)."
        }
        if (!isEndpointAllowed(parsed)) {
            return "Local LLM bridge blocked (insecure non-local endpoint)."
        }
        return "Local LLM bridge enabled: ${parsed.host}${parsed.encodedPath} · model $model · deterministic fallback active."
    }

    suspend fun queueReason(
        prompt: String,
        notes: List<UserNote>,
        priorSummaries: List<String>,
    ): LocalReasoningEngine.Output? = withContext(Dispatchers.IO) {
        if (!enabled) return@withContext null
        val url = endpoint.toHttpUrlOrNull() ?: return@withContext null
        if (!isEndpointAllowed(url)) return@withContext null

        val notesSnapshot = notes
            .take(16)
            .joinToString("\n") { "- ${it.title}: ${it.content.take(180)}" }
        val historySnapshot = priorSummaries
            .takeLast(8)
            .joinToString("\n") { "- ${it.take(180)}" }

        val instruction = """
            You are Atlas local reasoning engine.
            Return ONLY valid JSON:
            {"summary":"...","next_action":"...","confidence":0.0}
            Constraints:
            - summary <= 280 chars
            - next_action <= 180 chars
            - use prompt + memory context

            Prompt:
            $prompt

            Notes:
            $notesSnapshot

            Prior outputs:
            $historySnapshot
        """.trimIndent()

        val requestBody = ChatRequest(
            model = model,
            messages = listOf(
                ChatMessage("system", "Respond with concise operational output."),
                ChatMessage("user", instruction)
            ),
            temperature = 0.35,
            max_tokens = 420,
            stream = false,
        )
        val requestJson = json.encodeToString(ChatRequest.serializer(), requestBody)
        val req = Request.Builder()
            .url(url)
            .post(requestJson.toRequestBody("application/json".toMediaType()))
            .addHeader("Accept", "application/json")
            .addHeader("Cache-Control", "no-store")
            .build()

        val content = runCatching {
            okHttp.newCall(req).execute().use { rsp ->
                if (!rsp.isSuccessful) return@use null
                val body = rsp.body?.string().orEmpty()
                val parsed = json.decodeFromString(ChatResponse.serializer(), body)
                parsed.choices.firstOrNull()?.message?.content?.trim()
                    ?.ifEmpty { null }
                    ?: parsed.choices.firstOrNull()?.text?.trim()?.ifEmpty { null }
            }
        }.getOrNull() ?: return@withContext null

        val output = parseQueueOutput(content) ?: return@withContext null
        LocalReasoningEngine.Output(
            summary = output.summary.take(420),
            nextAction = output.nextAction.take(220),
            confidence = output.confidence.coerceIn(0.0, 1.0),
            model = "atlas-local-llm/${model.take(64)}",
        )
    }

    private data class QueueOutput(
        val summary: String,
        val nextAction: String,
        val confidence: Double,
    )

    private fun parseQueueOutput(raw: String): QueueOutput? {
        for (candidate in jsonCandidates(raw)) {
            val element = runCatching { json.parseToJsonElement(candidate) }.getOrNull() as? JsonObject ?: continue
            val summary = element.string("summary")
            val nextAction = element.string("next_action").ifEmpty { element.string("nextAction") }
            if (summary.isBlank() || nextAction.isBlank()) continue
            val confidence = element.double("confidence") ?: 0.66
            return QueueOutput(
                summary = summary.trim(),
                nextAction = nextAction.trim(),
                confidence = confidence,
            )
        }
        return null
    }

    private fun JsonObject.string(key: String): String {
        return (this[key] as? JsonPrimitive)?.contentOrNull.orEmpty()
    }

    private fun JsonObject.double(key: String): Double? {
        return (this[key] as? JsonPrimitive)?.doubleOrNull
    }

    private fun jsonCandidates(raw: String): List<String> {
        val trimmed = raw.trim()
        val candidates = mutableListOf(trimmed)

        val firstFence = trimmed.indexOf("```")
        if (firstFence >= 0) {
            val secondFence = trimmed.indexOf("```", startIndex = firstFence + 3)
            if (secondFence > firstFence) {
                var fenced = trimmed.substring(firstFence + 3, secondFence).trim()
                if (fenced.startsWith("json", ignoreCase = true)) {
                    fenced = fenced.removePrefix("json").removePrefix("JSON").trim()
                }
                if (fenced.isNotEmpty()) candidates += fenced
            }
        }

        extractBalanced(trimmed, '{', '}')?.let { candidates += it }
        extractBalanced(trimmed, '[', ']')?.let { candidates += it }
        return candidates
    }

    private fun extractBalanced(text: String, open: Char, close: Char): String? {
        var depth = 0
        var start = -1
        var inString = false
        var escaped = false
        text.forEachIndexed { idx, ch ->
            if (inString) {
                if (escaped) {
                    escaped = false
                    return@forEachIndexed
                }
                if (ch == '\\') {
                    escaped = true
                    return@forEachIndexed
                }
                if (ch == '"') {
                    inString = false
                }
                return@forEachIndexed
            }
            if (ch == '"') {
                inString = true
                return@forEachIndexed
            }
            if (ch == open) {
                if (depth == 0) start = idx
                depth += 1
            } else if (ch == close && depth > 0) {
                depth -= 1
                if (depth == 0 && start >= 0) {
                    return text.substring(start, idx + 1)
                }
            }
        }
        return null
    }

    private fun isEndpointAllowed(url: okhttp3.HttpUrl): Boolean {
        return when (url.scheme.lowercase()) {
            "https" -> true
            "http" -> {
                val host = url.host.lowercase()
                host == "localhost" || host == "127.0.0.1"
            }
            else -> false
        }
    }
}
