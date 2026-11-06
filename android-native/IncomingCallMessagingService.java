package com.webapp.erimaxmanuteno;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.media.AudioAttributes;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import androidx.core.app.NotificationCompat;
import com.capacitorjs.plugins.pushnotifications.MessagingService;
import com.google.firebase.messaging.RemoteMessage;
import java.util.Map;

public class IncomingCallMessagingService extends MessagingService {
  private static final String CHANNEL = "erimax_incoming_calls";

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
        .setStyle(new NotificationCompat.BigTextStyle().bigText(number + " • " + machine + "\\n" + sector))
        .build();
      NotificationManager nm = (NotificationManager)getSystemService(Context.NOTIFICATION_SERVICE);
      nm.notify(id.hashCode(), n);
    } else {
      super.onMessageReceived(message);
    }
  }

  private void createChannel() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      NotificationManager nm = getSystemService(NotificationManager.class);
      if (nm.getNotificationChannel(CHANNEL) != null) return;
      Uri sound = Uri.parse("android.resource://" + getPackageName() + "/raw/alarme");
      AudioAttributes attrs = new AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build();
      NotificationChannel ch = new NotificationChannel(CHANNEL, "Chamadas de O.S.", NotificationManager.IMPORTANCE_HIGH);
      ch.setDescription("Alerta sonoro de novas ordens de serviço");
      ch.enableVibration(true);
      ch.setSound(sound, attrs);
      ch.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
      nm.createNotificationChannel(ch);
    }
  }
}
