package com.nearbycoder.couchpotato.reminders

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.CalendarContract
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import com.nearbycoder.couchpotato.R
import com.nearbycoder.couchpotato.data.local.CouchNight
import com.nearbycoder.couchpotato.domain.TitleRef

/** Local reminders for couch nights via AlarmManager + NotificationManager. */
object Reminders {
    const val CHANNEL_ID = "couch_nights"
    const val EXTRA_TITLE = "title"
    const val EXTRA_BODY = "body"
    const val EXTRA_TITLE_KEY = "titleKey"
    const val EXTRA_NIGHT_ID = "nightId"

    fun ensureChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            val channel = NotificationChannel(CHANNEL_ID, "Couch nights", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Reminders for planned couch nights"
            }
            manager.createNotificationChannel(channel)
        }
    }

    fun hasNotificationPermission(context: Context): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun canScheduleExact(context: Context): Boolean {
        val alarms = context.getSystemService(AlarmManager::class.java)
        return Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()
    }

    /** Intent that opens the system page for granting exact-alarm access (Android 12+). */
    fun exactAlarmSettingsIntent(context: Context): Intent? =
        if (Build.VERSION.SDK_INT >= 31) {
            Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, "package:${context.packageName}".toUri())
        } else null

    fun schedule(context: Context, night: CouchNight, minutesBefore: Int) {
        cancel(context, night)
        if (!night.remind || night.isDone) return
        val fireAt = night.startsAt - minutesBefore * 60_000L
        if (fireAt <= System.currentTimeMillis()) return
        ensureChannel(context)
        val body = if (minutesBefore > 0) {
            "${night.titleName} starts in $minutesBefore minutes."
        } else {
            "${night.titleName} is on."
        }
        val intent = Intent(context, ReminderReceiver::class.java).apply {
            putExtra(EXTRA_TITLE, "Couch time")
            putExtra(EXTRA_BODY, body)
            putExtra(EXTRA_TITLE_KEY, night.titleKey)
            putExtra(EXTRA_NIGHT_ID, night.id)
        }
        val pending = PendingIntent.getBroadcast(
            context, night.id.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val alarms = context.getSystemService(AlarmManager::class.java)
        if (canScheduleExact(context)) {
            alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pending)
        } else {
            // Exact alarms aren't allowed; an inexact alarm still lands within a few minutes.
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pending)
        }
    }

    fun cancel(context: Context, night: CouchNight) {
        val intent = Intent(context, ReminderReceiver::class.java)
        val pending = PendingIntent.getBroadcast(
            context, night.id.hashCode(), intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        context.getSystemService(AlarmManager::class.java).cancel(pending)
        pending.cancel()
    }

    fun post(context: Context, title: String, body: String, titleKey: String?, id: Int) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        ensureChannel(context)
        val open = Intent(Intent.ACTION_VIEW, (titleKey?.let { "couchpotato://title/$it" } ?: "couchpotato://planner").toUri())
            .setPackage(context.packageName)
        val contentIntent = PendingIntent.getActivity(
            context, id, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(id, notification)
        } catch (_: SecurityException) {
            // Permission was revoked between the check and the call; nothing to show.
        }
    }
}

/** Adds couch nights to the system calendar through the standard insert intent. */
object CalendarBridge {
    fun insertIntent(night: CouchNight): Intent =
        Intent(Intent.ACTION_INSERT)
            .setData(CalendarContract.Events.CONTENT_URI)
            .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, night.startsAt)
            .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, night.endsAt)
            .putExtra(CalendarContract.Events.TITLE, night.titleName)
            .putExtra(
                CalendarContract.Events.DESCRIPTION,
                listOf(night.note, "Planned with Couch Potato", TitleRef.parse(night.titleKey)?.deepLink ?: "")
                    .filter { it.isNotBlank() }.joinToString("\n\n"),
            )
}
