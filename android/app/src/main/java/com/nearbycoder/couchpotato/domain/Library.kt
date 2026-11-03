package com.nearbycoder.couchpotato.domain

import com.nearbycoder.couchpotato.data.local.AppDatabase
import com.nearbycoder.couchpotato.data.local.CouchNight
import com.nearbycoder.couchpotato.data.local.SavedTitle
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn

/** Reads and writes the watchlist and planner. */
class Library(private val db: AppDatabase, scope: CoroutineScope) {
    private val titles = db.savedTitles()
    private val nights = db.couchNights()

    val savedTitles: StateFlow<List<SavedTitle>> = titles.observeAll().stateIn(scope, SharingStarted.Eagerly, emptyList())
    val couchNights: StateFlow<List<CouchNight>> = nights.observeAll().stateIn(scope, SharingStarted.Eagerly, emptyList())

    fun observe(key: String): Flow<SavedTitle?> = titles.observe(key)

    suspend fun saved(key: String): SavedTitle? = titles.get(key)

    suspend fun save(title: CatalogTitle, status: WatchStatus = WatchStatus.QUEUED): SavedTitle {
        val existing = titles.get(title.ref.key)
        val saved = existing?.updated(title)?.withStatus(status) ?: SavedTitle.from(title, status)
        titles.upsert(saved)
        return saved
    }

    suspend fun setStatus(key: String, status: WatchStatus) {
        val existing = titles.get(key) ?: return
        titles.upsert(existing.withStatus(status))
    }

    suspend fun update(title: SavedTitle) = titles.upsert(title.copy(updatedAt = System.currentTimeMillis()))

    suspend fun remove(key: String) {
        titles.delete(key)
    }

    suspend fun setRating(key: String, rating: Int) {
        val existing = titles.get(key) ?: return
        titles.upsert(existing.copy(rating = rating.coerceIn(0, 5), updatedAt = System.currentTimeMillis()))
    }

    suspend fun setNotes(key: String, notes: String) {
        val existing = titles.get(key) ?: return
        titles.upsert(existing.copy(notes = notes, updatedAt = System.currentTimeMillis()))
    }

    suspend fun setFollowing(key: String, following: Boolean) {
        val existing = titles.get(key) ?: return
        titles.upsert(existing.copy(isFollowing = following, updatedAt = System.currentTimeMillis()))
    }

    suspend fun setProgress(key: String, season: Int, episode: Int) {
        val existing = titles.get(key) ?: return
        val status = if (existing.watchStatus == WatchStatus.QUEUED) WatchStatus.WATCHING else existing.watchStatus
        titles.upsert(existing.copy(lastSeason = season, lastEpisode = episode, status = status.raw, updatedAt = System.currentTimeMillis()))
    }

    // Planner

    suspend fun addNight(night: CouchNight) = nights.upsert(night)
    suspend fun updateNight(night: CouchNight) = nights.upsert(night)
    suspend fun deleteNight(night: CouchNight) = nights.delete(night)
    suspend fun night(id: String): CouchNight? = nights.get(id)

    // Backup

    suspend fun allTitles(): List<SavedTitle> = titles.all()
    suspend fun allNights(): List<CouchNight> = nights.all()

    /** Merges imported titles: a title already here is only replaced by a newer copy. */
    suspend fun importTitles(list: List<SavedTitle>): Int {
        val newer = list.filter { incoming -> (titles.get(incoming.key)?.updatedAt ?: Long.MIN_VALUE) < incoming.updatedAt }
        titles.upsertAll(newer)
        return newer.size
    }

    /** Adds imported plans that aren't here yet (matched by id). */
    suspend fun importNights(list: List<CouchNight>): Int {
        val fresh = list.filter { nights.get(it.id) == null }
        nights.upsertAll(fresh)
        return fresh.size
    }
}
