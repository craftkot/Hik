package com.ehtid.game_lab

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs

/**
 * User opt-in TYPE_APPLICATION_OVERLAY. Never reads other apps' screen or RAM.
 * All fields are user-entered. Opens only this app, no background captures.
 */
class OverlayService : Service() {
    companion object {
        const val ACTION_STOP = "com.ehtid.game_lab.STOP_OVERLAY"
        const val PREFS = "ehtid_overlay"
        const val KEY_NUMBER = "pending_number"
        const val CHANNEL_ID = "ehtid_overlay_status"
        private const val NOTICE_ID = 4031
    }

    private lateinit var windows: WindowManager
    private var view: View? = null
    private var layout: WindowManager.LayoutParams? = null
    private var expanded = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windows = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val notifications = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notifications.createNotificationChannel(NotificationChannel(CHANNEL_ID,
            "EHTID floating editor", NotificationManager.IMPORTANCE_LOW))
        val launch = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val pending = PendingIntent.getActivity(this, 0, launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1,
            Intent(this, OverlayService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("EHTID · плавающее окно")
            .setContentText("Нажми для перехода к редактору сейвов")
            .setSmallIcon(android.R.drawable.ic_menu_edit)
            .setContentIntent(pending)
            .addAction(Notification.Action.Builder(
                android.R.drawable.ic_menu_close_clear_cancel, "Остановить", stop).build())
            .setOngoing(true)
            .build()
        startForeground(NOTICE_ID, notification)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (view == null) showBubble()
        return START_NOT_STICKY
    }

    private fun rounded(color: Int, radius: Float): GradientDrawable =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = radius * resources.displayMetrics.density
            setStroke((resources.displayMetrics.density * 1.4f).toInt(),
                Color.rgb(136, 96, 220))
        }

    private fun layoutParams(widthDp: Int, heightDp: Int): WindowManager.LayoutParams {
        val density = resources.displayMetrics.density
        val width = (widthDp * density).toInt()
        val height = (heightDp * density).toInt()
        return WindowManager.LayoutParams(width, height,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (resources.displayMetrics.widthPixels - width - 12).coerceAtLeast(0)
            y = (resources.displayMetrics.heightPixels / 3).coerceAtLeast(0)
        }
    }

    private fun showBubble() {
        detach()
        expanded = false
        val bubble = TextView(this).apply {
            text = "E"
            textSize = 26f
            setTextColor(Color.rgb(97, 232, 245))
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = rounded(Color.rgb(38, 24, 71), 22f)
            contentDescription = "Открыть плавающий редактор EHTID"
        }
        val params = layoutParams(62, 62)
        attach(bubble, params)
        dragOrTap(bubble) { showEditor() }
    }

    private fun showEditor() {
        detach()
        expanded = true
        val density = resources.displayMetrics.density
        val padding = (13 * density).toInt()
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padding, padding, padding, padding)
            background = rounded(Color.rgb(30, 23, 49), 16f)
        }
        val header = TextView(this).apply {
            text = "EHTID   ·   ЧИСЛО ИГРЫ"
            setTextColor(Color.rgb(118, 237, 246))
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, 0, (10 * density).toInt())
        }
        val info = TextView(this).apply {
            text = "Введи видимое HP, ману или валюту. Изменение памяти Android-игры недоступно без root."
            textSize = 12f
            setTextColor(Color.rgb(203, 193, 224))
            setPadding(0, 0, 0, (6 * density).toInt())
        }
        val number = EditText(this).apply {
            hint = "Например, 125"
            setSingleLine(true)
            inputType = android.text.InputType.TYPE_CLASS_NUMBER or
                android.text.InputType.TYPE_NUMBER_FLAG_DECIMAL or
                android.text.InputType.TYPE_NUMBER_FLAG_SIGNED
            setTextColor(Color.WHITE)
            setHintTextColor(Color.LTGRAY)
            textSize = 17f
        }
        val controls = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        val open = Button(this).apply {
            text = "Открыть редактор"
            isAllCaps = false
            setOnClickListener {
                val raw = number.text?.toString()?.trim() ?: ""
                // Do not parse arbitrary strings or pass executable payloads.
                val valid = Regex("^[+-]?[0-9]{1,12}([.,][0-9]{1,6})?$")
                if (raw.isNotEmpty() && !valid.matches(raw)) {
                    number.error = "Введи обычное число"
                    return@setOnClickListener
                }
                getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .edit().putString(KEY_NUMBER, raw.replace(',', '.')).apply()
                val launch = Intent(this@OverlayService, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                startActivity(launch)
                showBubble()
            }
        }
        val close = Button(this).apply {
            text = "×"
            contentDescription = "Закрыть плавающее окно"
            setOnClickListener { stopSelf() }
        }
        val minimize = Button(this).apply {
            text = "−"
            contentDescription = "Свернуть в пузырёк"
            setOnClickListener { showBubble() }
        }
        controls.addView(open, LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        controls.addView(minimize)
        controls.addView(close)
        panel.addView(header)
        panel.addView(info)
        panel.addView(number)
        panel.addView(controls)
        val params = layoutParams(333, 259).apply {
            flags = WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        }
        attach(panel, params)
        dragOrTap(header) { /* Drag header; taps do not edit the game. */ }
        number.setOnFocusChangeListener { _, focused ->
            if (focused) {
                (getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
                    .showSoftInput(number, InputMethodManager.SHOW_IMPLICIT)
            }
        }
    }

    private fun attach(widget: View, params: WindowManager.LayoutParams) {
        layout = params
        view = widget
        windows.addView(widget, params)
    }

    private fun detach() {
        view?.let {
            try { windows.removeView(it) } catch (_: IllegalArgumentException) { }
        }
        view = null
        layout = null
    }

    private fun dragOrTap(target: View, tap: () -> Unit) {
        var startX = 0
        var startY = 0
        var touchX = 0f
        var touchY = 0f
        var dragging = false
        val threshold = resources.displayMetrics.density * 7f
        target.setOnTouchListener { _, event ->
            val params = layout ?: return@setOnTouchListener false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = params.x
                    startY = params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    dragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - touchX
                    val dy = event.rawY - touchY
                    if (abs(dx) > threshold || abs(dy) > threshold) dragging = true
                    if (dragging) {
                        params.x = (startX + dx).toInt().coerceAtLeast(0)
                        params.y = (startY + dy).toInt().coerceAtLeast(0)
                        view?.let { windows.updateViewLayout(it, params) }
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!dragging) tap()
                    true
                }
                else -> false
            }
        }
    }

    override fun onDestroy() {
        detach()
        super.onDestroy()
    }
}
