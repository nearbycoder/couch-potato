package com.nearbycoder.couchpotato.reminders

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra(Reminders.EXTRA_TITLE) ?: "Couch time"
        val body = intent.getStringExtra(Reminders.EXTRA_BODY) ?: "Your couch night is starting."
        val titleKey = intent.getStringExtra(Reminders.EXTRA_TITLE_KEY)
        val nightId = intent.getStringExtra(Reminders.EXTRA_NIGHT_ID) ?: body
        Reminders.post(context, title, body, titleKey, nightId.hashCode())
    }
}
