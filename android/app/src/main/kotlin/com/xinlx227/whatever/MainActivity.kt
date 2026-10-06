package com.xinlx227.whatever

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun popSystemNavigator(): Boolean {
        // Root Back returns home while retaining the live engine and session.
        moveTaskToBack(true)
        return true
    }
}
