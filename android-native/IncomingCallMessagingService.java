package com.webapp.erimaxmanuteno;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.KeyguardManager;
import android.content.Context;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.Ringtone;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import android.os.Vibrator;
import android.os.VibrationEffect;
import androidx.core.app.NotificationCompat;
import com.capacitorjs.plugins.pushnotifications.MessagingService;
import com.google.firebase.messaging.RemoteMessage;
import java.util.Map;

public class IncomingCallMessagingService extends MessagingService {
  // Canal novo e silencioso: o toque é controlado por um único Ringtone,
  // para que SILENCIAR consiga interrompê-lo em todos os aparelhos.
  private static final String CHANNEL = "erimax_incoming_calls_v5";
  private static Ringtone activeAlarm;
  private static Vibrator activeVibrator;

  @Override public void onMessageReceived(RemoteMessage message) {
    Map<String,String> data = message.getData();
    if (data != null && data.containsKey("os_id")) {
      String id = data.get("os_id");
      String machine = data.getOrDefault("maquina", "Nova ordem de serviço");
      String sector = data.getOrDefault("setor", "Manutenção");
      String number = data.getOrDefault("numero", "Nova O.S.");
      createChannel();
      Intent screen = new Intent(this, IncomingCallActivity.class);
      screen.putExtra("os_id", id);
      screen.putExtra("maquina", machine);
      screen.putExtra("setor", sector);
      screen.putExtra("numero", number);
      screen.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
      PendingIntent full = PendingIntent.getActivity(this, id.hashCode(), screen,
        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
      Notification n = new NotificationCompat.Builder(this, CHANNEL)
        .setSound(null)
        .setVibrate(null)
        .setSmallIcon(getApplicationInfo().icon)
        .setContentTitle("Nova ordem de serviço")
        .setContentText(machine + " • " + sector)
        .setCategory(NotificationCompat.CATEGORY_CALL)
        .setPriority(NotificationCompat.PRIORITY_MAX)
        .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        .setOngoing(true)
        .setAutoCancel(false)
        .setFullScreenIntent(full, true)
        .setContentIntent(full)
        .setStyle(new NotificationCompat.BigTextStyle().bigText(number + " • " + machine + "\n" + sector))
        .build();
      NotificationManager nm = (NotificationManager)getSystemService(Context.NOTIFICATION_SERVICE);
      nm.notify(id.hashCode(), n);
      vibrateForIncomingOS();
      KeyguardManager keyguard = (KeyguardManager)getSystemService(Context.KEYGUARD_SERVICE);
      if (keyguard != null && !keyguard.isKeyguardLocked()) startAlertAlarm(this);
    } else {
      super.onMessageReceived(message);
    }
  }

  public static synchronized void startAlertAlarm(Context context) {
    stopAlert();
    try {
      Uri sound = Uri.parse("android.resource://" + context.getPackageName() + "/raw/alarme");
      activeAlarm = RingtoneManager.getRingtone(context.getApplicationContext(), sound);
      if (activeAlarm != null) {
        if (Build.VERSION.SDK_INT >= 21) {
          activeAlarm.setAudioAttributes(new AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build());
        }
        if (Build.VERSION.SDK_INT >= 28) activeAlarm.setLooping(true);
        activeAlarm.play();
      }
    } catch (Exception ignored) { stopAlert(); }
  }

  public static synchronized void stopAlert() {
    if (activeAlarm != null) {
      try { activeAlarm.stop(); } catch (Exception ignored) { }
      activeAlarm = null;
    }
    if (activeVibrator != null) {
      try { activeVibrator.cancel(); } catch (Exception ignored) { }
      activeVibrator = null;
    }
  }

  private void vibrateForIncomingOS() {
    try {
      Vibrator vibrator = (Vibrator)getSystemService(Context.VIBRATOR_SERVICE);
      if (vibrator == null || !vibrator.hasVibrator()) return;
      activeVibrator = vibrator;
      long[] pattern = new long[]{0, 700, 350, 700, 350, 1000};
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1));
      } else {
        vibrator.vibrate(pattern, -1);
      }
    } catch (Exception ignored) { }
  }

  private void createChannel() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      NotificationManager nm = getSystemService(NotificationManager.class);
      if (nm.getNotificationChannel(CHANNEL) != null) return;
      NotificationChannel ch = new NotificationChannel(CHANNEL, "Alertas de O.S. EriMax", NotificationManager.IMPORTANCE_HIGH);
      ch.setDescription("Aviso visual; o toque é controlado pelo aplicativo");
      ch.setSound(null, null);
      ch.enableVibration(false);
      ch.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
      nm.createNotificationChannel(ch);
    }
  }
}