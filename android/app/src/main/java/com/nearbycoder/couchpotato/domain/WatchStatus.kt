package com.nearbycoder.couchpotato.domain

enum class WatchStatus(val raw: String, val label: String, val shortLabel: String) {
    QUEUED("queued", "Want to Watch", "Want"),
    WATCHING("watching", "Watching", "Watching"),
    WATCHED("watched", "Watched", "Watched"),
    DROPPED("dropped", "Dropped", "Dropped");

    companion object {
        fun fromRaw(raw: String?): WatchStatus = entries.firstOrNull { it.raw == raw } ?: QUEUED
    }
}
