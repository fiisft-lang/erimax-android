package com.webapp.erimaxmanuteno;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.KeyguardManager;
import android.content.Context;
import android.graphics.Color;
import android.content.Intent;
import android.os.Build;
import android.os.Vibrator;
import android.os.VibrationEffect;
import androidx.core.app.NotificationCompat;
import com.capacitorjs.plugins.pushnotifications.MessagingService;
import com.google.firebase.messaging.RemoteMessage;
import java.util.Map;

public class IncomingCallMessagingService extends MessagingService {
  private static final String CHANNEL = "erimax_incoming_calls_v5";

  @Override public void onMessageReceived(RemoteMessage message) {
    Map<String,String> data = message.getData();
    if (data != null && data.containsKey("os_id")) {
      String id = data.get("os_id");
      String machine = data.getOrDefault("maquina", "Nova ordem de serviço");
      String sector = data.getOrDefault("setor", "Manutenção");
      String number = data.getOrDefault("numero", "Nova O.S.");
      boolean transferencia = "transferencia_os".equals(data.get("acao"));
      String tipoAlerta = data.getOrDefault("tipo_alerta", "");
      boolean preventiva = "preventiva_lembrete".equals(tipoAlerta) || "preventiva_atrasada".equals(tipoAlerta);
      boolean preventivaAtrasada = "preventiva_atrasada".equals(tipoAlerta);
      createChannel();
      Intent screen = new Intent(this, IncomingCallActivity.class);
      screen.putExtra("os_id", id);
      screen.putExtra("maquina", machine);
      screen.putExtra("setor", sector);
      screen.putExtra("numero", number);
      screen.putExtra("problema", data.getOrDefault("problema", "Não informado"));
      screen.putExtra("tipo_alerta", tipoAlerta);
      screen.putExtra("servico", data.getOrDefault("servico", data.getOrDefault("problema", "Serviço preventivo")));
      screen.putExtra("prazo", data.getOrDefault("prazo", "Não informado"));
      screen.putExtra("maquinas", data.getOrDefault("maquinas", machine));
      screen.putExtra("acao", transferencia ? "transferencia_os" : "nova_os");
      screen.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
      PendingIntent full = PendingIntent.getActivity(this, id.hashCode(), screen,
        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
      NotificationCompat.Builder builder = new NotificationCompat.Builder(this, CHANNEL)
        .setSound(null)
        .setVibrate(null)
        .setSmallIcon(getApplicationInfo().icon)
        .setColor(Color.rgb(16, 43, 58))
        .setColorized(true)
        .setSubText("ERIMAX • MANUTENÇÃO")
        .setContentTitle(preventiva
          ? (preventivaAtrasada ? "Preventiva atrasada" : "Lembrete de preventiva")
          : (transferencia ? "O.S. aguardando seu aceite" : "Nova ordem de serviço"))
        .setContentText(preventiva
          ? data.getOrDefault("servico", "Serviço preventivo") + " • " + sector
          : (transferencia ? number + " • " + machine + " • " + sector : machine + " • " + sector))
        .setCategory(NotificationCompat.CATEGORY_CALL)
        .setPriority(NotificationCompat.PRIORITY_MAX)
        .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        .setOngoing(true)
        .setAutoCancel(false)
        .setFullScreenIntent(full, true)
        .setContentIntent(full)
        .setStyle(new NotificationCompat.BigTextStyle().bigText(preventiva
          ? data.getOrDefault("servico", "Serviço preventivo") + "\\n" + sector + "\\n" + data.getOrDefault("maquinas", machine) + "\\nPrazo: " + data.getOrDefault("prazo", "Não informado")
          : number + " • " + machine + "\\n" + sector));
      if (preventiva) {
        builder.addAction(android.R.drawable.ic_menu_view, preventivaAtrasada ? "Abrir O.S." : "Começar preventiva",
          preventivaActionIntent(data, preventivaAtrasada ? "abrir_preventiva" : "iniciar_preventiva"));
        if (!preventivaAtrasada) builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Adiar",
          preventivaActionIntent(data, "adiar_preventiva"));
      } else {
        builder.addAction(android.R.drawable.ic_menu_view, transferencia ? "Aceitar transferência" : "Assumir",
          actionIntent(id, machine, sector, number, transferencia ? "aceitar_transferencia" : "assumir"));
        builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, transferencia ? "Recusar transferência" : "Silenciar",
          actionIntent(id, machine, sector, number, transferencia ? "recusar_transferencia" : "silenciar"));
      }
      Notification n = builder.build();
      NotificationManager nm = (NotificationManager)getSystemService(Context.NOTIFICATION_SERVICE);
      nm.notify(id.hashCode(), n);
      vibrateForIncomingOS();
      KeyguardManager keyguard = (KeyguardManager)getSystemService(Context.KEYGUARD_SERVICE);
      // Transferências também precisam tocar com a tela bloqueada: não dependem
      // de a Activity de tela cheia conseguir abrir no Android.
      startAlertAlarm(this);
    } else {
      super.onMessageReceived(message);
    }
  }

  private PendingIntent preventivaActionIntent(Map<String,String> data, String action) {
    String id = data.getOrDefault("os_id", "");
    Intent intent = new Intent(this, IncomingCallActivity.class);
    intent.putExtra("os_id", id);
    intent.putExtra("maquina", data.getOrDefault("maquina", "Manutenção"));
    intent.putExtra("setor", data.getOrDefault("setor", "Setor não informado"));
    intent.putExtra("numero", data.getOrDefault("numero", "O.S. " + id));
    intent.putExtra("problema", data.getOrDefault("servico", "Serviço preventivo"));
    intent.putExtra("tipo_alerta", data.getOrDefault("tipo_alerta", "preventiva_lembrete"));
    intent.putExtra("servico", data.getOrDefault("servico", "Serviço preventivo"));
    intent.putExtra("prazo", data.getOrDefault("prazo", "Não informado"));
    intent.putExtra("maquinas", data.getOrDefault("maquinas", "Não informadas"));
    intent.putExtra("notification_action", action);
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
    int requestCode = (id + ":" + action).hashCode();
    return PendingIntent.getActivity(this, requestCode, intent,
      PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
  }

  private PendingIntent actionIntent(String id, String machine, String sector, String number, String action) {
    Intent intent = new Intent(this, IncomingCallActivity.class);
    intent.putExtra("os_id", id);
    intent.putExtra("maquina", machine);
    intent.putExtra("setor", sector);
    intent.putExtra("numero", number);
    intent.putExtra("problema", "");
    intent.putExtra("notification_action", action);
    intent.putExtra("acao", ("aceitar_transferencia".equals(action) || "recusar_transferencia".equals(action)) ? "transferencia_os" : "nova_os");
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
    int requestCode = (id + ":" + action).hashCode();
    return PendingIntent.getActivity(this, requestCode, intent,
      PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
  }

  public static void startAlertAlarm(Context context) {
    Intent service = new Intent(context, IncomingAlertService.class);
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(service);
    else context.startService(service);
  }

  public static void stopAlert(Context context) {
    context.stopService(new Intent(context, IncomingAlertService.class));
    try {
      Vibrator vibrator = (Vibrator)context.getSystemService(Context.VIBRATOR_SERVICE);
      if (vibrator != null) vibrator.cancel();
    } catch (Exception ignored) { }
  }

  private void vibrateForIncomingOS() {
    try {
      Vibrator vibrator = (Vibrator)getSystemService(Context.VIBRATOR_SERVICE);
      if (vibrator == null || !vibrator.hasVibrator()) return;
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