package com.nearbycoder.couchpotato.domain.ai

import android.util.Log
import androidx.compose.runtime.Immutable
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.SystemInstruction
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Availability of the on-device model (Gemini Nano via AICore). */
@Immutable
sealed interface AiStatus {
    /** Not checked yet. Treated like [Unsupported] by UI that hides itself. */
    data object Checking : AiStatus
    data object Unsupported : AiStatus
    data object Downloadable : AiStatus
    /** [progress] is 0–1, or null when the size isn't known yet. */
    data class Downloading(val progress: Float? = null) : AiStatus
    data object Ready : AiStatus

    /** True when on-device features should be offered at all. */
    val isOffered: Boolean get() = this is Downloadable || this is Downloading || this is Ready
}

/**
 * Wraps ML Kit's GenAI Prompt API. Owned by the AppContainer; the model client is created
 * lazily on first use. Never throws for an unsupported device: anything that goes wrong while
 * checking ends in [AiStatus.Unsupported].
 */
class OnDeviceAI(private val scope: CoroutineScope) {
    private val _status = MutableStateFlow<AiStatus>(AiStatus.Checking)
    val status: StateFlow<AiStatus> = _status

    private val lock = Mutex()
    private var model: GenerativeModel? = null
    private var checked = false
    private var systemPromptSupported: Boolean? = null
    private var downloadJob: Job? = null

    /** Checks availability once; later calls are no-ops. Safe to call from any screen. */
    fun checkIfNeeded() {
        if (checked) return
        scope.launch { check() }
    }

    private suspend fun check(force: Boolean = false) {
        val status = lock.withLock {
            if (checked && !force) return
            checked = true
            try {
                when (client().checkStatus()) {
                    FeatureStatus.AVAILABLE -> AiStatus.Ready
                    FeatureStatus.DOWNLOADABLE -> AiStatus.Downloadable
                    FeatureStatus.DOWNLOADING -> AiStatus.Downloading()
                    else -> AiStatus.Unsupported
                }
            } catch (e: CancellationException) {
                checked = false
                throw e
            } catch (t: Throwable) {
                Log.i(TAG, "On-device model unavailable: ${t.message}")
                AiStatus.Unsupported
            }
        }
        _status.value = status
        // AICore may already be fetching the model; follow along so progress shows.
        if (status is AiStatus.Downloading) startDownload()
    }

    /**
     * Makes the model usable: checks status and starts the download if needed, then waits
     * for it. Returns true when the model is ready.
     */
    suspend fun ensureReady(): Boolean {
        if (!checked) check()
        if (_status.value is AiStatus.Downloadable) startDownload()
        val settled = _status.first { it !is AiStatus.Checking && it !is AiStatus.Downloading }
        return settled is AiStatus.Ready
    }

    /** Starts (or follows) the model download in the container's scope. */
    fun startDownload() {
        if (downloadJob?.isActive == true) return
        downloadJob = scope.launch {
            _status.value = AiStatus.Downloading()
            var total = 0L
            try {
                client().download().collect { s ->
                    when (s) {
                        is DownloadStatus.DownloadStarted -> {
                            total = s.bytesToDownload
                            _status.value = AiStatus.Downloading(if (total > 0) 0f else null)
                        }
                        is DownloadStatus.DownloadProgress -> _status.value = AiStatus.Downloading(
                            if (total > 0) (s.totalBytesDownloaded.toFloat() / total).coerceIn(0f, 1f) else null,
                        )
                        is DownloadStatus.DownloadCompleted -> _status.value = AiStatus.Ready
                        is DownloadStatus.DownloadFailed -> {
                            Log.w(TAG, "Model download failed: ${s.e.message}")
                            check(force = true)
                        }
                        else -> {}
                    }
                }
                if (_status.value is AiStatus.Downloading) check(force = true)
            } catch (e: CancellationException) {
                throw e
            } catch (t: Throwable) {
                Log.w(TAG, "Model download failed: ${t.message}")
                check(force = true)
            }
        }
    }

    /** One-shot generation. Throws when the model isn't ready or generation fails. */
    suspend fun generate(prompt: String, instructions: String?, temperature: Float, maxTokens: Int): String {
        val request = request(prompt, instructions, temperature, maxTokens)
        val response = client().generateContent(request)
        return response.candidates.firstOrNull()?.text.orEmpty()
    }

    /** Streaming generation; emits the accumulated text after every chunk. */
    fun stream(prompt: String, instructions: String?, temperature: Float, maxTokens: Int): Flow<String> = flow {
        val request = request(prompt, instructions, temperature, maxTokens)
        val text = StringBuilder()
        client().generateContentStream(request).collect { chunk ->
            val piece = chunk.candidates.firstOrNull()?.text.orEmpty()
            if (piece.isNotEmpty()) {
                // Chunks are documented as deltas; if a build sends the full text so far, take it as is.
                if (piece.startsWith(text)) text.setLength(0)
                text.append(piece)
                emit(text.toString())
            }
        }
    }

    fun close() {
        runCatching { model?.close() }
        model = null
    }

    private suspend fun request(prompt: String, instructions: String?, temperature: Float, maxTokens: Int) =
        if (instructions != null && supportsSystemPrompt()) {
            generateContentRequest(SystemInstruction(instructions), TextPart(prompt)) {
                this.temperature = temperature
                this.topK = 16
                this.maxOutputTokens = maxTokens
            }
        } else {
            val text = if (instructions != null) "$instructions\n\n$prompt" else prompt
            generateContentRequest(TextPart(text)) {
                this.temperature = temperature
                this.topK = 16
                this.maxOutputTokens = maxTokens
            }
        }

    private suspend fun supportsSystemPrompt(): Boolean {
        systemPromptSupported?.let { return it }
        val supported = try {
            client().isSystemPromptAvailable()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            false
        }
        systemPromptSupported = supported
        return supported
    }

    @Synchronized
    private fun client(): GenerativeModel = model ?: Generation.getClient().also { model = it }

    private companion object {
        const val TAG = "OnDeviceAI"
    }
}
