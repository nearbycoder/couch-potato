package com.nearbycoder.couchpotato.ui.ask

import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.nearbycoder.couchpotato.AppContainer
import com.nearbycoder.couchpotato.domain.CatalogTitle
import com.nearbycoder.couchpotato.domain.ai.AiStatus
import com.nearbycoder.couchpotato.domain.ai.AskQuery
import com.nearbycoder.couchpotato.domain.ai.Prompts
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class AskPhase { IDLE, THINKING, SEARCHING, DONE }

@Immutable
data class AskState(
    val text: String = "",
    val phase: AskPhase = AskPhase.IDLE,
    /** The request the current results answer. */
    val request: String = "",
    val query: AskQuery? = null,
    val titles: List<CatalogTitle> = emptyList(),
    /** True when nothing matched exactly and some filters were loosened. */
    val relaxed: Boolean = false,
    /** Shown when the model couldn't answer; results then come from a plain text search. */
    val modelError: String? = null,
    /** Shown when the catalog couldn't be reached. */
    val error: String? = null,
) {
    val busy: Boolean get() = phase == AskPhase.THINKING || phase == AskPhase.SEARCHING
}

class AskViewModel(private val container: AppContainer) : ViewModel() {
    private val ai = container.ai
    val status: StateFlow<AiStatus> = ai.status

    private val _state = MutableStateFlow(AskState())
    val state: StateFlow<AskState> = _state
    private var job: Job? = null

    val examples = listOf(
        "Something funny under an hour",
        "A cozy mystery series",
        "Highly rated sci-fi from the last 5 years",
        "A thriller on Netflix",
    )

    init { ai.checkIfNeeded() }

    fun setText(text: String) = _state.update { it.copy(text = text) }

    fun download() = ai.startDownload()

    fun ask(request: String = _state.value.text) {
        val text = request.trim()
        if (text.isEmpty()) return
        job?.cancel()
        job = viewModelScope.launch {
            _state.update {
                AskState(text = text, phase = AskPhase.THINKING, request = text, query = it.query, titles = it.titles)
            }
            var modelError: String? = null
            val query = if (ai.status.value is AiStatus.Ready) {
                try {
                    val raw = ai.generate(Prompts.askRequest(text), Prompts.askInstructions(), temperature = 0.1f, maxTokens = 256)
                    AskQuery.parse(raw, text) ?: AskQuery.fallback(text)
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Throwable) {
                    modelError = "The on-device model couldn't answer, so these are plain search results."
                    AskQuery.fallback(text)
                }
            } else {
                AskQuery.fallback(text)
            }
            _state.update { it.copy(phase = AskPhase.SEARCHING, query = query, modelError = modelError) }
            try {
                val result = container.askFinder.find(query)
                _state.update {
                    it.copy(phase = AskPhase.DONE, query = result.query, titles = result.titles, relaxed = result.relaxed)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (t: Throwable) {
                _state.update {
                    it.copy(phase = AskPhase.DONE, titles = emptyList(), error = t.message ?: "Couldn't load titles.")
                }
            }
        }
    }
}
