package com.quintus.dev

import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import android.view.*
import kotlin.math.abs

class FloatingBubbleService : Service() {

    private lateinit var windowManager: WindowManager
    private var bubbleView: View? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()

        // ✅ 1) 오버레이 권한 체크
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !Settings.canDrawOverlays(this)
        ) {
            Log.e("FloatingBubbleService", "Overlay permission not granted. Stopping service.")
            stopSelf()
            return
        }

        // ✅ 2) WindowManager & 버블 뷰 세팅
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        val inflater = LayoutInflater.from(this)
        bubbleView = inflater.inflate(R.layout.layout_floating_bubble, null)

        val layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = 50
            y = 200
        }

        windowManager.addView(bubbleView, layoutParams)

        // ✅ 3) onTouch 하나로 클릭 + 드래그 모두 처리
        bubbleView?.setOnTouchListener(object : View.OnTouchListener {
            private var initialX: Int = 0
            private var initialY: Int = 0
            private var initialTouchX: Float = 0f
            private var initialTouchY: Float = 0f

            private val clickThreshold = 10 // px

            override fun onTouch(v: View?, event: MotionEvent?): Boolean {
                event ?: return false

                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = layoutParams.x
                        initialY = layoutParams.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        return true
                    }

                    MotionEvent.ACTION_MOVE -> {
                        layoutParams.x = initialX + (initialTouchX - event.rawX).toInt()
                        layoutParams.y = initialY + (event.rawY - initialTouchY).toInt()
                        windowManager.updateViewLayout(bubbleView, layoutParams)
                        return true
                    }

                    MotionEvent.ACTION_UP -> {
                        val dx = abs(event.rawX - initialTouchX)
                        val dy = abs(event.rawY - initialTouchY)

                        // 거의 안 움직였으면 "클릭"으로 간주
                        if (dx < clickThreshold && dy < clickThreshold) {
                            openAppFromBubble()
                        }
                        return true
                    }
                }
                return false
            }
        })
    }

    /**
     * 버블을 "클릭"했을 때 앱을 여는 로직
     * → Intent 에 fromBubble=true 플래그를 심어서 MainActivity 로 전달
     */
    private fun openAppFromBubble() {
        val extraKey = "fromBubble"

        // 런처와 동일한 Intent 가져와서 플래그 추가
        val launchIntent =
            packageManager.getLaunchIntentForPackage(packageName)?.apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
                )
                putExtra(extraKey, true)
            }

        if (launchIntent != null) {
            startActivity(launchIntent)
        } else {
            // 혹시 모를 fallback: MainActivity 직접 호출
            val fallbackIntent = Intent(this, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP
                )
                putExtra(extraKey, true)
            }
            startActivity(fallbackIntent)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        bubbleView?.let {
            windowManager.removeView(it)
            bubbleView = null
        }
    }
}
