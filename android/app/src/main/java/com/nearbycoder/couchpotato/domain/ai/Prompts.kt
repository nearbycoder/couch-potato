package com.nearbycoder.couchpotato.domain.ai

import com.nearbycoder.couchpotato.domain.CatalogTitle
import com.nearbycoder.couchpotato.domain.MediaKind
import com.nearbycoder.couchpotato.domain.Mood
import com.nearbycoder.couchpotato.domain.TimeBudget
import com.nearbycoder.couchpotato.domain.runtimeLabel
import java.time.LocalDate

/** Prompt text for the on-device model. Kept pure so it can be unit-tested. */
object Prompts {
    /** System-style preamble for "Ask Couch Potato": the allowed values plus a few examples. */
    fun askInstructions(today: LocalDate = LocalDate.now()): String = """
You turn a request for something to watch into search settings for a streaming guide app.
Reply with ONLY one JSON object, no prose and no code fences, with exactly these keys:
{"kind": "movie|series|any",
 "genre": "action|animation|comedy|crime|documentary|drama|family|scifi|horror|mystery|romance|reality|none",
 "years": "any|thisYear|last5|y2020s|y2010s|y2000s|y1990s|older",
 "minRating": 0|6|7|8,
 "sort": "popular|newest|rating",
 "mood": "cozy|laughs|thrills|feels|spooky|brainy|none",
 "maxMinutes": 0,
 "services": ["netflix","hulu","disney","hbo","apple","prime","peacock","paramount","starz","amc","crunchyroll","tubi","youtube"],
 "keywords": "",
 "summary": ""}
Rules:
- Leave every field at its default unless the request explicitly says it.
- Use only the listed values. Use "any", "none", 0, [] or "" when the request doesn't say.
- maxMinutes is the longest runtime wanted in minutes (0 means no limit).
- services lists only streaming services the request names.
- Use keywords only for a specific title, person or franchise; leave it empty for general requests.
- Never invent services, ratings or time limits.
- summary is a short restatement in title case words, at most 8 words.
- "highly rated" means minRating 7 and sort "rating". "new" or "recent" means years "last5".
- Today is ${today.year}.
Examples:
Request: Something funny under an hour
{"kind":"any","genre":"comedy","years":"any","minRating":0,"sort":"popular","mood":"laughs","maxMinutes":60,"services":[],"keywords":"","summary":"Comedies under an hour"}
Request: A cozy mystery series
{"kind":"series","genre":"mystery","years":"any","minRating":0,"sort":"popular","mood":"cozy","maxMinutes":0,"services":[],"keywords":"","summary":"Cozy mystery series"}
Request: Recent sci-fi shows on Netflix
{"kind":"series","genre":"scifi","years":"last5","minRating":0,"sort":"popular","mood":"none","maxMinutes":0,"services":["netflix"],"keywords":"","summary":"Recent sci-fi series on Netflix"}
""".trim()

    fun askRequest(request: String): String = "Request: ${request.trim()}\n"

    /** System-style preamble for the Shuffle pitch. */
    const val PITCH_INSTRUCTIONS: String =
        "You are a friend recommending what to watch tonight. Write one or two sentences, at most 35 words, " +
            "warm and specific to this title. No spoilers beyond the premise. No emoji, no hashtags, no quotation marks. " +
            "Don't start with the title's name. Don't use the word \"perfect\". Reply with the sentences only."

    fun pitchRequest(title: CatalogTitle, mood: Mood?, budget: TimeBudget): String = buildString {
        appendLine("Title: ${title.name}")
        title.year?.let { appendLine("Year: $it") }
        appendLine("Kind: ${if (title.kind == MediaKind.MOVIE) "movie" else "series"}")
        if (title.genres.isNotEmpty()) appendLine("Genres: ${title.genres.take(4).joinToString(", ")}")
        title.runtime?.takeIf { it > 0 }?.let {
            appendLine("Runtime: ${it.runtimeLabel}${if (title.kind == MediaKind.TV) " per episode" else ""}")
        }
        val overview = title.overview.trim()
        if (overview.isNotEmpty()) appendLine("Premise: ${overview.take(600)}")
        mood?.let { appendLine("Tonight's mood: ${it.title} (${it.blurb.trimEnd('.')})") }
        if (budget.minutes > 0) appendLine("Time available: ${budget.label.lowercase()}")
    }.trim()

    /**
     * Tidies a (possibly partial, streaming) pitch: drops wrapping quotes, emoji and hashtags,
     * collapses whitespace and stops after two sentences.
     */
    fun cleanPitch(raw: String): String {
        var text = raw
            .replace(Regex("#\\w+"), "")
            .let(::stripEmoji)
            .replace(Regex("\\s+"), " ")
            .trim()
            .trim('"', '“', '”', '\'')
            .trim()
        val sentences = Regex("[^.!?]+[.!?]+").findAll(text).map { it.value }.toList()
        if (sentences.size >= 2) {
            val two = sentences.take(2).joinToString("") { it }.trim()
            if (two.length < text.length) text = two
        }
        return text
    }

    private fun stripEmoji(text: String): String {
        val out = StringBuilder(text.length)
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            val type = Character.getType(cp)
            val isEmoji = type == Character.OTHER_SYMBOL.toInt() ||
                type == Character.SURROGATE.toInt() ||
                cp == 0xFE0F || cp == 0x200D || cp in 0x1F3FB..0x1F3FF
            if (!isEmoji) out.appendCodePoint(cp)
            i += Character.charCount(cp)
        }
        return out.toString()
    }
}
