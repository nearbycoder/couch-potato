package com.nearbycoder.couchpotato.data.local

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.Transaction
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface SavedTitleDao {
    @Query("SELECT * FROM saved_titles ORDER BY updated_at DESC")
    fun observeAll(): Flow<List<SavedTitle>>

    @Query("SELECT * FROM saved_titles WHERE `key` = :key LIMIT 1")
    fun observe(key: String): Flow<SavedTitle?>

    @Query("SELECT * FROM saved_titles WHERE `key` = :key LIMIT 1")
    suspend fun get(key: String): SavedTitle?

    @Query("SELECT * FROM saved_titles")
    suspend fun all(): List<SavedTitle>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(title: SavedTitle)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(titles: List<SavedTitle>)

    @Update
    suspend fun update(title: SavedTitle)

    @Query("DELETE FROM saved_titles WHERE `key` = :key")
    suspend fun delete(key: String)

    @Query("DELETE FROM saved_titles")
    suspend fun clear()
}

@Dao
interface CouchNightDao {
    @Query("SELECT * FROM couch_nights ORDER BY starts_at ASC")
    fun observeAll(): Flow<List<CouchNight>>

    @Query("SELECT * FROM couch_nights")
    suspend fun all(): List<CouchNight>

    @Query("SELECT * FROM couch_nights WHERE id = :id LIMIT 1")
    suspend fun get(id: String): CouchNight?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(night: CouchNight)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(nights: List<CouchNight>)

    @Update
    suspend fun update(night: CouchNight)

    @Delete
    suspend fun delete(night: CouchNight)

    @Query("DELETE FROM couch_nights WHERE title_key = :titleKey")
    suspend fun deleteForTitle(titleKey: String)

    @Transaction
    suspend fun replaceAll(nights: List<CouchNight>) {
        clear()
        upsertAll(nights)
    }

    @Query("DELETE FROM couch_nights")
    suspend fun clear()
}

@Database(entities = [SavedTitle::class, CouchNight::class], version = 1, exportSchema = false)
abstract class AppDatabase : RoomDatabase() {
    abstract fun savedTitles(): SavedTitleDao
    abstract fun couchNights(): CouchNightDao

    companion object {
        fun build(context: Context): AppDatabase =
            Room.databaseBuilder(context.applicationContext, AppDatabase::class.java, "couch-potato.db")
                .fallbackToDestructiveMigration(dropAllTables = true)
                .build()
    }
}
