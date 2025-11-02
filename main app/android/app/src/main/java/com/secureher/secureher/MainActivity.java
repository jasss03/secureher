package com.secureher.secureher;

import android.Manifest;
import android.content.pm.PackageManager;
import android.telephony.SmsManager;

import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "secureher/sms";
    private static final int REQ_SEND_SMS = 9911;
    private MethodChannel.Result pendingResult;
    private List<String> pendingRecipients;
    private String pendingMessage;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler(this::onMethodCall);
    }

    private void onMethodCall(MethodCall call, MethodChannel.Result result) {
        if ("sendText".equals(call.method)) {
            @SuppressWarnings("unchecked")
            ArrayList<String> to = (ArrayList<String>) ((HashMap) call.arguments).get("to");
            String message = (String) ((HashMap) call.arguments).get("message");
            sendSms(to, message, result);
        } else {
            result.notImplemented();
        }
    }

    private void sendSms(List<String> recipients, String message, MethodChannel.Result result) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
            this.pendingResult = result;
            this.pendingRecipients = recipients;
            this.pendingMessage = message;
            ActivityCompat.requestPermissions(this, new String[]{Manifest.permission.SEND_SMS}, REQ_SEND_SMS);
            return;
        }
        try {
            SmsManager sms = SmsManager.getDefault();
            for (String number : recipients) {
                sms.sendTextMessage(number, null, message, null, null);
                try { Thread.sleep(300); } catch (InterruptedException ignored) {}
            }
            result.success(true);
        } catch (Exception e) {
            result.success(false);
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQ_SEND_SMS && pendingResult != null) {
            boolean granted = grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED;
            if (granted) {
                sendSms(pendingRecipients, pendingMessage, pendingResult);
            } else {
                pendingResult.success(false);
            }
            pendingResult = null;
            pendingRecipients = null;
            pendingMessage = null;
        }
    }
}
