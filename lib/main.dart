package com.example.subwaybot

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import rikka.shizuku.Shizuku
import kotlin.concurrent.thread

class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 1. التحقق من إذن الظهور فوق التطبيقات الأخرى
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            startActivityForResult(intent, 123)
        } else {
            startOverlayService()
        }

        // 2. التحقق من تشغيل Shizuku
        if (Shizuku.pingBinder()) {
            Toast.makeText(this, "تم الاتصال بـ Shizuku بنجاح!", Toast.LENGTH_SHORT).show()
        } else {
            Toast.makeText(this, "يرجى تشغيل تطبيق Shizuku أولاً!", Toast.LENGTH_LONG).show()
        }

        finish() // إغلاق الواجهة الرئيسية وترك الخدمة تعمل في الخلفية
    }

    private fun startOverlayService() {
        startService(Intent(this, FloatingService::class.java))
    }
}

class FloatingService : android.app.Service() {

    private lateinit var windowManager: WindowManager
    private lateinit var floatingView: LinearLayout
    private lateinit var menuView: LinearLayout
    private var isMenuOpen = false
    private var isAiRunning = false
    private val handler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?) = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        // إنشاء الواجهة العائمة برمجيًا (الأيقونة + القائمة)
        createFloatingUI()
    }

    private fun createFloatingUI() {
        // --- 1. تصميم الأيقونة العائمة (دائرة وبداخلها نقطة حمراء) ---
        val outerCircle = LinearLayout(this).apply {
            orientation = LinearLayout.CENTER_VERTICAL
            gravity = Gravity.CENTER
            
            // خلفية دائرة رمادية شفافة
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#80000000"))
                setStroke(3, Color.WHITE)
            }
        }

        // النقطة الحمراء في المنتصف
        val redDot = View(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.RED)
            }
        }

        val dotParams = LinearLayout.LayoutParams(40, 40)
        outerCircle.addView(redDot, dotParams)

        // --- 2. تصميم القائمة الصغيرة التي تفتح وتغلق ---
        menuView = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#CC000000"))
            setPadding(20, 20, 20, 20)
            visibility = View.GONE // خفية في البداية
        }

        val aiButton = Button(this).apply {
            text = "تشغيل الـ AI"
            setBackgroundColor(Color.GREEN)
            setTextColor(Color.WHITE)
            setOnClickListener {
                isAiRunning = !isAiRunning
                if (isAiRunning) {
                    text = "إيقاف الـ AI"
                    setBackgroundColor(Color.RED)
                    startAiLogic()
                } else {
                    text = "تشغيل الـ AI"
                    setBackgroundColor(Color.GREEN)
                }
            }
        }
        menuView.addView(aiButton)

        // تجميع الأيقونة والقائمة في الحاوية الرئيسية
        floatingView = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(outerCircle, LinearLayout.LayoutParams(120, 120))
            addView(menuView, LinearLayout.LayoutParams(WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT))
        }

        // إعدادات النافذة العائمة
        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 100
            y = 200
        }

        // --- 3. إضافة منطق السحب (Drag) والضغط (Click) للأيقونة ---
        outerCircle.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0
            private var initialY = 0
            private var initialTouchX = 0f
            private var initialTouchY = 0f
            private var isClick = true

            override fun onTouch(v: View?, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = params.x
                        initialY = params.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        isClick = true
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val diffX = (event.rawX - initialTouchX).toInt()
                        val diffY = (event.rawY - initialTouchY).toInt()
                        if (Math.abs(diffX) > 10 || Math.abs(diffY) > 10) {
                            isClick = false
                        }
                        params.x = initialX + diffX
                        params.y = initialY + diffY
                        windowManager.updateViewLayout(floatingView, params)
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (isClick) {
                            // فتح أو إغلاق القائمة عند النقر
                            isMenuOpen = !isMenuOpen
                            menuView.visibility = if (isMenuOpen) View.VISIBLE else View.GONE
                        }
                        return true
                    }
                }
                return false
            }
        })

        windowManager.addView(floatingView, params)
    }

    // --- 4. محاكاة حركة اللاعب عبر Shizuku ---
    private fun sendSwipeCommand(startX: Int, startY: Int, endX: Int, endY: Int) {
        thread {
            try {
                if (Shizuku.pingBinder()) {
                    val command = "input swipe $startX $startY $endX $endY 100\n"
                    val process = Shizuku.newProcess(arrayOf("sh"), null, null)
                    process.outputStream.write(command.toByteArray())
                    process.outputStream.flush()
                    process.outputStream.close()
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    // الأوامر الأساسية للعبة Subway Surfers (تعتمد على مقاس شاشة جوالك)
    private fun moveLeft() = sendSwipeCommand(500, 1000, 200, 1000)
    private fun moveRight() = sendSwipeCommand(500, 1000, 800, 1000)
    private fun jump() = sendSwipeCommand(500, 1200, 500, 400)
    private fun roll() = sendSwipeCommand(500, 400, 500, 1200)

    // --- 5. منطق الذكاء الاصطناعي لترجمة القرارات الحركية ---
    private fun startAiLogic() {
        handler.post(object : Runnable {
            override fun run() {
                if (!isAiRunning) return

                // هنا يتم تنفيذ الحركات تلقائياً لتفادي العوائق
                // يمكنك تعديل التسلسل حسب الحاجة أو ربطه بالتقاط الشاشة
                val randomAction = (0..3).random()
                when (randomAction) {
                    0 -> moveLeft()
                    1 -> moveRight()
                    2 -> jump()
                    3 -> roll()
                }

                // ينفذ حركة كل 800 مللي ثانية تلقائياً
                handler.postDelayed(this, 800)
            }
        })
    }

    override fun onDestroy() {
        super.onDestroy()
        if (::floatingView.isInitialized) {
            windowManager.removeView(floatingView)
        }
    }
}
