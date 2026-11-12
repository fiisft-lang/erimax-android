package com.webapp.erimaxmanuteno;

import android.app.Activity;
import android.app.NotificationManager;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

public class IncomingCallActivity extends Activity {
  private String osId = "";

  @Override protected void onCreate(Bundle state) {
    super.onCreate(state);
    if (Build.VERSION.SDK_INT >= 27) setShowWhenLocked(true);
    if (Build.VERSION.SDK_INT >= 27) setTurnScreenOn(true);
    getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    getWindow().setStatusBarColor(Color.BLACK);
    getWindow().setNavigationBarColor(Color.BLACK);
    osId = getIntent().getStringExtra("os_id");
    if (osId == null) osId = "";
    String notificationAction = getIntent().getStringExtra("notification_action");
    if ("silenciar".equals(notificationAction)) { dismissCall(); return; }
    if ("assumir".equals(notificationAction) || "aceitar_transferencia".equals(notificationAction)) { answerCall(); return; }
    boolean transferencia = "transferencia_os".equals(getIntent().getStringExtra("acao"));
    String machine = getIntent().getStringExtra("maquina");
    String sector = getIntent().getStringExtra("setor");
    String number = getIntent().getStringExtra("numero");
    IncomingCallMessagingService.startAlertAlarm(this);

    LinearLayout root = new LinearLayout(this);
    root.setOrientation(1);
    root.setGravity(Gravity.CENTER);
    root.setPadding(dp(24), dp(42), dp(24), dp(34));
    root.setBackgroundColor(Color.BLACK);

    TextView brand = label("ERIMAX • MANUTENÇÃO", 15, Color.rgb(160, 174, 192));
    TextView title = label(transferencia ? "TRANSFERÊNCIA DE O.S. AGUARDANDO ACEITE" : "NOVA ORDEM DE SERVIÇO", 23, Color.WHITE);
    title.setTypeface(null, Typeface.BOLD);
    TextView detail = label((number == null ? "Nova O.S." : number)
      + "\nSetor: " + (sector == null ? "Não informado" : sector)
      + "\nMáquina: " + (machine == null ? "Não informada" : machine), 20, Color.WHITE);
    detail.setTypeface(null, Typeface.BOLD);
    root.addView(brand);
    root.addView(title);
    root.addView(detail);
    root.addView(label("Deslize uma das opções para continuar", 14, Color.LTGRAY));
    addSwipeAction(root, transferencia ? "DESLIZE PARA ACEITAR A TRANSFERÊNCIA" : "DESLIZE PARA ACEITAR A O.S.", "➜", Color.rgb(22, 163, 74), true, this::answerCall);
    addSwipeAction(root, "DESLIZE PARA SILENCIAR", "⬅", Color.rgb(220, 38, 38), false, this::dismissCall);
    setContentView(root);
  }

  private int dp(int value) {
    return (int)(value * getResources().getDisplayMetrics().density + 0.5f);
  }

  private void addSwipeAction(LinearLayout root, String hint, String arrow, int color, boolean leftToRight, Runnable action) {
    FrameLayout track = new FrameLayout(this);
    track.setBackgroundColor(leftToRight ? Color.rgb(15, 76, 42) : Color.rgb(112, 28, 34));
    LinearLayout.LayoutParams trackParams = new LinearLayout.LayoutParams(-1, dp(68));
    trackParams.setMargins(0, dp(18), 0, 0);
    TextView hintView = label(hint, 13, Color.WHITE);
    hintView.setTypeface(null, Typeface.BOLD);
    track.addView(hintView, new FrameLayout.LayoutParams(-1, -1));

    TextView thumb = label(arrow, 25, Color.WHITE);
    thumb.setTypeface(null, Typeface.BOLD);
    thumb.setBackgroundColor(color);
    FrameLayout.LayoutParams thumbParams = new FrameLayout.LayoutParams(dp(76), -1,
      leftToRight ? Gravity.LEFT : Gravity.RIGHT);
    track.addView(thumb, thumbParams);

    final float[] downX = {0};
    final float[] startX = {0};
    thumb.setOnTouchListener((View v, MotionEvent event) -> {
      float max = Math.max(0, track.getWidth() - thumb.getWidth());
      switch (event.getAction()) {
        case MotionEvent.ACTION_DOWN:
          downX[0] = event.getRawX();
          startX[0] = thumb.getTranslationX();
          return true;
        case MotionEvent.ACTION_MOVE:
          float dx = event.getRawX() - downX[0];
          float next = startX[0] + dx;
          next = Math.max(leftToRight ? 0 : -max, Math.min(leftToRight ? max : 0, next));
          thumb.setTranslationX(next);
          return true;
        case MotionEvent.ACTION_UP:
        case MotionEvent.ACTION_CANCEL:
          float moved = Math.abs(thumb.getTranslationX() - startX[0]);
          if (event.getAction() == MotionEvent.ACTION_UP && moved >= max * 0.62f) {
            action.run();
          } else {
            thumb.animate().translationX(0).setDuration(160).start();
          }
          return true;
      }
      return true;
    });
    root.addView(track, trackParams);
  }
  private void stopAlarm() {
    IncomingCallMessagingService.stopAlert();
  }

  private TextView label(String text,int size,int color) {
    TextView v = new TextView(this); v.setText(text); v.setTextSize(size); v.setTextColor(color); v.setGravity(Gravity.CENTER); v.setPadding(dp(8),dp(12),dp(8),dp(12)); return v;
  }

  private void answerCall() {
    stopAlarm(); dismissNotification();
    String action = "transferencia_os".equals(getIntent().getStringExtra("acao")) ? "aceitar_transferencia" : "assumir";
    Intent open = new Intent(Intent.ACTION_VIEW,Uri.parse("erimax://os/" + Uri.encode(osId) + "?action=" + action),this,MainActivity.class);
    open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
    startActivity(open); finish();
  }

  private void dismissCall() {
    stopAlarm();
    dismissNotification();
    finish();
  }

  private void dismissNotification() {
    ((NotificationManager)getSystemService(NOTIFICATION_SERVICE)).cancel(osId.hashCode());
  }

  @Override protected void onDestroy() {
    stopAlarm();
    super.onDestroy();
  }
}