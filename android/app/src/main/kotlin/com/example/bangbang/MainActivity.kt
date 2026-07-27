package com.bangbang.game

import android.media.MediaPlayer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "bangbang/audio"
    private var music: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    if (music == null) {
                        music = MediaPlayer().apply {
                            setDataSource(applicationContext, android.net.Uri.parse("android.resource://$packageName/${R.raw.western_theme}"))
                            isLooping = true
                            setVolume(.35f, .35f)
                            prepare()
                        }
                    }
                    music?.start()
                    result.success(null)
                }
                "stop" -> { music?.pause(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    override fun onDestroy() { music?.release(); music = null; super.onDestroy() }
}
