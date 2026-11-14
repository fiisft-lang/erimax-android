package com.webapp.erimaxmanuteno;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.MediaPlayer;
import android.net.Uri;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import androidx.core.app.NotificationCompat;

/** Alarme independente da Activity da tela bloqueada. */
public class IncomingAlertService extends Service {
  private static final String CHANNEL = "erimax_persistent_alarm_v1";
  private static final int NOTIFICATION_ID = 9821;
  private MediaPlayer player;
  @Override public void onCreate() { super.onCreate(); createChannel(); }
  @Override public int onStartCommand(Intent intent, int flags, int startId) {
    Notification notification = new NotificationCompat.Builder(this, CHANNEL)
      .setSmallIcon(getApplicationInfo().icon)
      .setContentTitle("EriMax • Alerta de manutenção")
      .setContentText("Aguardando ação na ordem de serviço")
      .setCategory(NotificationCompat.CATEGORY_SERVICE)
      .setPriority(NotificationCompat.PRIORITY_LOW).setOngoing(true).setSilent(true).build();
    if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION_ID, notification,
      android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
    else startForeground(NOTIFICATION_ID, notification);
    startLoopingAlarm();
    return START_STICKY;
  }
  private void startLoopingAlarm() {
    if (player != null && player.isPlaying()) return;
    releasePlayer();
    try {
      player = new MediaPlayer();
      player.setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build());
      player.setWakeMode(getApplicationContext(), PowerManager.PARTIAL_WAKE_LOCK);
      Uri sound = Uri.parse("android.resource://" + getPackageName() + "/" + R.raw.alarme);
      player.setDataSource(this, sound);
      player.setLooping(true);
      player.setOnErrorListener((mp, what, extra) -> { releasePlayer(); stopSelf(); return true; });
      player.prepare();
      player.start();
    } catch (Exception error) { releasePlayer(); stopSelf(); }
  }
  private void createChannel() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      NotificationManager manager = getSystemService(NotificationManager.class);
      if (manager.getNotificationChannel(CHANNEL) == null) {
        NotificationChannel channel = new NotificationChannel(CHANNEL, "Alarme contínuo EriMax", NotificationManager.IMPORTANCE_LOW);
        channel.setDescription("Alarme de O.S. aguardando ação.");
        channel.setSound(null, null); channel.enableVibration(false); manager.createNotificationChannel(channel);
      }
    }
  }
  private void releasePlayer() {
    if (player != null) {
      try { if (player.isPlaying()) player.stop(); } catch (Exception ignored) { }
      try { player.reset(); } catch (Exception ignored) { }
      try { player.release(); } catch (Exception ignored) { }
      player = null;
    }
  }
  @Override public void onDestroy() { releasePlayer(); stopForeground(true); super.onDestroy(); }
  @Override public IBinder onBind(Intent intent) { return null; }
}
