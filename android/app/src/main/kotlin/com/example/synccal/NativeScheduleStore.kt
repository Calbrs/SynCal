package com.example.SynCal

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * Persists scheduled message data to a local SQLite database so that
 * SmsForegroundService can process the queue robustly in the background.
 */
object NativeScheduleStore {

    private const val TAG = "NativeScheduleStore"
    private const val DB_NAME = "native_schedules.db"
    private const val DB_VERSION = 1
    private const val TABLE_NAME = "schedules"

    // Status constants
    const val STATUS_PENDING = "pending"
    const val STATUS_PROCESSING = "processing"  // Atomically claimed; mid-send
    const val STATUS_SENT = "sent"
    const val STATUS_FAILED = "failed"

    data class NativeRecipient(val name: String, val phone: String)

    data class NativeSchedule(
        val scheduleId: String,
        val message: String,
        val triggerAtMillis: Long,
        val simSlot: Int,
        var status: String,
        val recipients: List<NativeRecipient>
    )

    private class DbHelper(context: Context) : SQLiteOpenHelper(context, DB_NAME, null, DB_VERSION) {
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL(
                """
                CREATE TABLE $TABLE_NAME (
                    scheduleId TEXT PRIMARY KEY,
                    message TEXT,
                    triggerAtMillis INTEGER,
                    simSlot INTEGER,
                    status TEXT,
                    recipients TEXT
                )
                """.trimIndent()
            )
        }

        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            db.execSQL("DROP TABLE IF EXISTS $TABLE_NAME")
            onCreate(db)
        }
    }

    private var dbHelper: DbHelper? = null

    @Synchronized
    private fun getDb(context: Context): SQLiteDatabase {
        if (dbHelper == null) {
            dbHelper = DbHelper(context.applicationContext)
        }
        return dbHelper!!.writableDatabase
    }

    // ---- Read ----------------------------------------------------------------

    fun getAll(context: Context): List<NativeSchedule> {
        val list = mutableListOf<NativeSchedule>()
        try {
            getDb(context).query(TABLE_NAME, null, null, null, null, null, null).use { cursor ->
                while (cursor.moveToNext()) {
                    val id = cursor.getString(cursor.getColumnIndexOrThrow("scheduleId"))
                    val msg = cursor.getString(cursor.getColumnIndexOrThrow("message"))
                    val time = cursor.getLong(cursor.getColumnIndexOrThrow("triggerAtMillis"))
                    val sim = cursor.getInt(cursor.getColumnIndexOrThrow("simSlot"))
                    val stat = cursor.getString(cursor.getColumnIndexOrThrow("status"))
                    val recipsStr = cursor.getString(cursor.getColumnIndexOrThrow("recipients"))

                    val schedule = NativeSchedule(
                        scheduleId = id,
                        message = msg,
                        triggerAtMillis = time,
                        simSlot = sim,
                        status = stat,
                        recipients = parseRecipients(recipsStr)
                    )
                    list.add(schedule)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "getAll error: ${e.message}")
        }
        return list
    }

    fun getPending(context: Context): List<NativeSchedule> {
        val list = mutableListOf<NativeSchedule>()
        try {
            getDb(context).query(
                TABLE_NAME, null, "status = ?", arrayOf(STATUS_PENDING),
                null, null, null
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    val id = cursor.getString(cursor.getColumnIndexOrThrow("scheduleId"))
                    val msg = cursor.getString(cursor.getColumnIndexOrThrow("message"))
                    val time = cursor.getLong(cursor.getColumnIndexOrThrow("triggerAtMillis"))
                    val sim = cursor.getInt(cursor.getColumnIndexOrThrow("simSlot"))
                    val stat = cursor.getString(cursor.getColumnIndexOrThrow("status"))
                    val recipsStr = cursor.getString(cursor.getColumnIndexOrThrow("recipients"))

                    list.add(NativeSchedule(id, msg, time, sim, stat, parseRecipients(recipsStr)))
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "getPending error: ${e.message}")
        }
        return list
    }

    fun getDue(context: Context): List<NativeSchedule> {
        val list = mutableListOf<NativeSchedule>()
        val now = System.currentTimeMillis().toString()
        try {
            getDb(context).query(
                TABLE_NAME, null, "status = ? AND triggerAtMillis <= ?", 
                arrayOf(STATUS_PENDING, now),
                null, null, null
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    val id = cursor.getString(cursor.getColumnIndexOrThrow("scheduleId"))
                    val msg = cursor.getString(cursor.getColumnIndexOrThrow("message"))
                    val time = cursor.getLong(cursor.getColumnIndexOrThrow("triggerAtMillis"))
                    val sim = cursor.getInt(cursor.getColumnIndexOrThrow("simSlot"))
                    val stat = cursor.getString(cursor.getColumnIndexOrThrow("status"))
                    val recipsStr = cursor.getString(cursor.getColumnIndexOrThrow("recipients"))

                    list.add(NativeSchedule(id, msg, time, sim, stat, parseRecipients(recipsStr)))
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "getDue error: ${e.message}")
        }
        return list
    }

    // ---- Write ---------------------------------------------------------------

    /**
     * Atomically transitions a schedule from STATUS_PENDING → STATUS_PROCESSING.
     *
     * Returns true if this caller is the first to claim it (i.e. the UPDATE
     * actually modified a row). Returns false if another path already claimed
     * or sent it, meaning this caller must skip sending entirely.
     *
     * This is the de-duplication gate for both the native send path and the
     * Dart headless engine path. Both paths call this before doing any work.
     */
    @Synchronized
    fun claimForSending(context: Context, scheduleId: String): Boolean {
        return try {
            val cv = ContentValues().apply { put("status", STATUS_PROCESSING) }
            val rows = getDb(context).update(
                TABLE_NAME, cv,
                "scheduleId = ? AND status = ?",
                arrayOf(scheduleId, STATUS_PENDING)
            )
            val claimed = rows > 0
            Log.d(TAG, "claimForSending($scheduleId): ${if (claimed) "CLAIMED" else "already claimed/sent — skipped"}")
            claimed
        } catch (e: Exception) {
            Log.e(TAG, "claimForSending error: ${e.message}")
            false
        }
    }

    /**
     * Returns the current native status for a single schedule, or null if not found.
     * Used by the Dart headless path to check whether the native Kotlin path
     * has already claimed or sent a schedule before creating a Flutter session.
     */
    fun getStatus(context: Context, scheduleId: String): String? {
        return try {
            getDb(context).query(
                TABLE_NAME, arrayOf("status"),
                "scheduleId = ?", arrayOf(scheduleId),
                null, null, null
            ).use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (e: Exception) {
            Log.e(TAG, "getStatus error: ${e.message}")
            null
        }
    }

    fun saveSchedule(context: Context, schedule: NativeSchedule) {
        try {
            val cv = ContentValues().apply {
                put("scheduleId", schedule.scheduleId)
                put("message", schedule.message)
                put("triggerAtMillis", schedule.triggerAtMillis)
                put("simSlot", schedule.simSlot)
                put("status", schedule.status)
                put("recipients", serialiseRecipients(schedule.recipients))
            }
            getDb(context).replace(TABLE_NAME, null, cv)
            Log.d(TAG, "Saved schedule ${schedule.scheduleId} (status=${schedule.status})")
        } catch (e: Exception) {
            Log.e(TAG, "saveSchedule error: ${e.message}")
        }
    }

    fun markAsSent(context: Context, scheduleId: String) {
        updateStatus(context, scheduleId, STATUS_SENT)
        Log.d(TAG, "Marked sent: $scheduleId")
    }

    fun markAsFailed(context: Context, scheduleId: String) {
        updateStatus(context, scheduleId, STATUS_FAILED)
        Log.d(TAG, "Marked failed: $scheduleId")
    }

    fun delete(context: Context, scheduleId: String) {
        try {
            getDb(context).delete(TABLE_NAME, "scheduleId = ?", arrayOf(scheduleId))
            Log.d(TAG, "Deleted schedule: $scheduleId")
        } catch (e: Exception) {
            Log.e(TAG, "delete error: ${e.message}")
        }
    }

    fun clear(context: Context) {
        try {
            getDb(context).delete(TABLE_NAME, null, null)
            Log.d(TAG, "Cleared all native schedules")
        } catch (e: Exception) {
            Log.e(TAG, "clear error: ${e.message}")
        }
    }

    // ---- Serialise JSON → Map (for Dart sync) --------------------------------

    fun toSyncMap(schedule: NativeSchedule): Map<String, Any> = mapOf(
        "scheduleId" to schedule.scheduleId,
        "status" to schedule.status
    )

    // ---- Private helpers -----------------------------------------------------

    private fun updateStatus(context: Context, scheduleId: String, newStatus: String) {
        try {
            val cv = ContentValues().apply { put("status", newStatus) }
            getDb(context).update(TABLE_NAME, cv, "scheduleId = ?", arrayOf(scheduleId))
        } catch (e: Exception) {
            Log.e(TAG, "updateStatus error: ${e.message}")
        }
    }

    private fun serialiseRecipients(recipients: List<NativeRecipient>): String {
        val arr = JSONArray()
        recipients.forEach { r ->
            arr.put(JSONObject().put("name", r.name).put("phone", r.phone))
        }
        return arr.toString()
    }

    private fun parseRecipients(jsonStr: String): List<NativeRecipient> {
        return try {
            val arr = JSONArray(jsonStr)
            (0 until arr.length()).map { i ->
                val r = arr.getJSONObject(i)
                NativeRecipient(
                    name = r.optString("name", ""),
                    phone = r.optString("phone", "")
                )
            }.filter { it.phone.isNotEmpty() }
        } catch (e: Exception) {
            emptyList()
        }
    }
}
