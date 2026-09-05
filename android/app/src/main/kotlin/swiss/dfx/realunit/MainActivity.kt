package swiss.realunit.app

import android.os.Handler
import android.os.Looper
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val installReferrerChannel = "swiss.realunit.app/install_referrer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, installReferrerChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "readInstallReferrer") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                readInstallReferrer(result)
            }
    }

    private fun readInstallReferrer(result: MethodChannel.Result) {
        val client = InstallReferrerClient.newBuilder(this).build()
        val main = Handler(Looper.getMainLooper())
        var replied = false

        fun reply(value: String?) {
            if (replied) return
            replied = true
            result.success(value)
            try {
                client.endConnection()
            } catch (_: Exception) {
            }
        }

        main.postDelayed({ reply(null) }, 3000)
        try {
            client.startConnection(
                object : InstallReferrerStateListener {
                    override fun onInstallReferrerSetupFinished(responseCode: Int) {
                        if (responseCode != InstallReferrerClient.InstallReferrerResponse.OK) {
                            reply(null)
                            return
                        }
                        try {
                            reply(client.installReferrer.installReferrer)
                        } catch (_: Exception) {
                            reply(null)
                        }
                    }

                    override fun onInstallReferrerServiceDisconnected() {}
                },
            )
        } catch (_: Exception) {
            reply(null)
        }
    }
}
