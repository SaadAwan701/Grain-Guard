package pk.grainguard.grainguard

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelId = "storage_alerts"
    private val notifications by lazy { getSystemService(NotificationManager::class.java) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (Build.VERSION.SDK_INT >= 26) {
            notifications.createNotificationChannel(
                NotificationChannel(channelId, "GrainGuard alerts", NotificationManager.IMPORTANCE_HIGH)
            )
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "grainguard/alerts")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
                            !getPreferences(MODE_PRIVATE).getBoolean("notificationPermissionRequested", false)
                        ) {
                            getPreferences(MODE_PRIVATE).edit().putBoolean("notificationPermissionRequested", true).apply()
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 41)
                        } else if (Build.VERSION.SDK_INT >= 26) {
                            startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                        } else {
                            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.fromParts("package", packageName, null)))
                        }
                        result.success(null)
                    }
                    "show" -> {
                        val id = call.argument<String>("id")
                        val title = call.argument<String>("title")
                        val body = call.argument<String>("body")
                        if (id == null || title == null || body == null) {
                            result.error("invalid_alert", "Missing notification details", null)
                        } else {
                            postAlert(id, title, body)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun postAlert(id: String, title: String, body: String) {
        if (!notifications.areNotificationsEnabled()) return
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val open = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val action = PendingIntent.getActivity(this, 0, open, PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channelId)
            else Notification.Builder(this).setPriority(Notification.PRIORITY_HIGH)
                .setDefaults(Notification.DEFAULT_ALL)
        notifications.notify(id, 1, builder
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(action)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setOnlyAlertOnce(true)
            .setAutoCancel(true)
            .build())
    }
}
