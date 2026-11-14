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
    getWindow().setStatusBarColor(Color.rgb(248, 250, 252));
    getWindow().setNavigationBarColor(Color.rgb(248, 250, 252));
    getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
    osId = getIntent().getStringExtra("os_id");
    if (osId == null) osId = "";
    String notificationAction = getIntent().getStringExtra("notification_action");
    if ("silenciar".equals(notificationAction)) { dismissCall(); return; }
    if ("recusar_transferencia".equals(notificationAction)) { rejectTransfer(); return; }
    if ("assumir".equals(notificationAction) || "aceitar_transferencia".equals(notificationAction)) { answerCall(); return; }
    boolean transferencia = "transferencia_os".equals(getIntent().getStringExtra("acao"));
    String machine = getIntent().getStringExtra("maquina");
    String sector = getIntent().getStringExtra("setor");
    String number = getIntent().getStringExtra("numero");
    String problem = getIntent().getStringExtra("problema");
    IncomingCallMessagingService.startAlertAlarm(this);

    LinearLayout root = new LinearLayout(this);
    root.setOrientation(1);
    root.setGravity(Gravity.CENTER);
    root.setPadding(dp(20), dp(28), dp(20), dp(24));
    root.setBackgroundColor(Color.rgb(248, 250, 252));

    TextView brand = label("ERIMAX  •  MANUTENÇÃO", 13, Color.rgb(100, 116, 139));
    TextView title = label(transferencia ? "Transferência de O.S." : "Nova ordem de serviço", 23, Color.rgb(15, 23, 42));
    title.setTypeface(null, Typeface.BOLD);
    TextView detail = label((number == null ? "Nova O.S." : number)
      + "\n\nSETOR\n" + (sector == null ? "Não informado" : sector)
      + "\n\nMÁQUINA\n" + (machine == null ? "Não informada" : machine)
      + "\n\nPROBLEMA DA MÁQUINA\n" + (problem == null || problem.trim().isEmpty() ? "Não informado" : problem.trim()), 16, Color.rgb(30, 41, 59));
    detail.setTypeface(null, Typeface.BOLD);
    root.addView(brand);
    root.addView(title);
    android.graphics.drawable.GradientDrawable infoBg = new android.graphics.drawable.GradientDrawable();
    infoBg.setColor(Color.WHITE);
    infoBg.setCornerRadius(dp(18));
    infoBg.setStroke(dp(1), Color.rgb(226, 232, 240));
    detail.setBackground(infoBg);
    detail.setPadding(dp(18), dp(18), dp(18), dp(18));
    LinearLayout.LayoutParams detailParams = new LinearLayout.LayoutParams(-1, -2);
    detailParams.setMargins(0, dp(18), 0, dp(12));
    root.addView(detail, detailParams);
    root.addView(label("Arraste o botão para cima para escolher", 14, Color.rgb(100, 116, 139)));
    LinearLayout actions = new LinearLayout(this);
    actions.setOrientation(0);
    actions.setGravity(Gravity.CENTER);
    actions.setPadding(0, dp(12), 0, 0);
    addSwipeAction(actions, transferencia ? "ACEITAR TRANSFERÊNCIA" : "ACEITAR O.S.", "✓", Color.rgb(22, 163, 74), this::answerCall);
    addSwipeAction(actions, transferencia ? "RECUSAR TRANSFERÊNCIA" : "SILENCIAR", transferencia ? "✕" : "🔕", Color.rgb(220, 38, 38), transferencia ? this::rejectTransfer : this::dismissCall);
    root.addView(actions);
    setContentView(root);
  }

  private int dp(int value) {
    return (int)(value * getResources().getDisplayMetrics().density + 0.5f);
  }

  private void addSwipeAction(LinearLayout row, String hint, String symbol, int color, Runnable action) {
    LinearLayout item = new LinearLayout(this);
    item.setOrientation(1);
    item.setGravity(Gravity.CENTER_HORIZONTAL);
    LinearLayout.LayoutParams itemParams = new LinearLayout.LayoutParams(0, -2, 1f);
    itemParams.setMargins(dp(7), 0, dp(7), 0);

    TextView title = label(hint, 12, Color.rgb(51, 65, 85));
    title.setTypeface(null, Typeface.BOLD);
    item.addView(title, new LinearLayout.LayoutParams(-1, dp(48)));

    FrameLayout track = new FrameLayout(this);
    android.graphics.drawable.GradientDrawable trackBg = new android.graphics.drawable.GradientDrawable();
    trackBg.setColor(Color.rgb(241, 245, 249));
    trackBg.setCornerRadius(dp(34));
    trackBg.setStroke(dp(1), Color.rgb(203, 213, 225));
    track.setBackground(trackBg);
    LinearLayout.LayoutParams trackParams = new LinearLayout.LayoutParams(dp(82), dp(148));
    trackParams.gravity = Gravity.CENTER_HORIZONTAL;
    trackParams.topMargin = dp(5);

    TextView hintView = label("↑", 22, Color.rgb(100, 116, 139));
    hintView.setTypeface(null, Typeface.BOLD);
    FrameLayout.LayoutParams hintParams = new FrameLayout.LayoutParams(-1, dp(48), Gravity.TOP);
    track.addView(hintView, hintParams);

    TextView thumb = label(symbol, 25, Color.WHITE);
    thumb.setTypeface(null, Typeface.BOLD);
    android.graphics.drawable.GradientDrawable thumbBg = new android.graphics.drawable.GradientDrawable();
    thumbBg.setColor(color);
    thumbBg.setShape(android.graphics.drawable.GradientDrawable.OVAL);
    thumb.setBackground(thumbBg);
    FrameLayout.LayoutParams thumbParams = new FrameLayout.LayoutParams(dp(66), dp(66), Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
    thumbParams.bottomMargin = dp(5);
    track.addView(thumb, thumbParams);

    final float[] downY = {0};
    final float[] startY = {0};
    thumb.setOnTouchListener((View v, MotionEvent event) -> {
      float max = Math.max(0, track.getHeight() - thumb.getHeight() - dp(10));
      switch (event.getAction()) {
        case MotionEvent.ACTION_DOWN:
          downY[0] = event.getRawY();
          startY[0] = thumb.getTranslationY();
          return true;
        case MotionEvent.ACTION_MOVE:
          float dy = event.getRawY() - downY[0];
          float next = startY[0] + dy;
          next = Math.max(-max, Math.min(0, next));
          thumb.setTranslationY(next);
          return true;
        case MotionEvent.ACTION_UP:
        case MotionEvent.ACTION_CANCEL:
          float moved = Math.abs(thumb.getTranslationY() - startY[0]);
          if (event.getAction() == MotionEvent.ACTION_UP && moved >= max * 0.62f) {
            action.run();
          } else {
            thumb.animate().translationY(0).setDuration(180).start();
          }
          return true;
      }
      return true;
    });
    item.addView(track, trackParams);
    TextView instruction = label("ARRASTE PARA CIMA", 10, Color.rgb(100, 116, 139));
    item.addView(instruction, new LinearLayout.LayoutParams(-1, dp(34)));
    row.addView(item, itemParams);
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

  private void rejectTransfer() {
    stopAlarm(); dismissNotification();
    Intent open = new Intent(Intent.ACTION_VIEW, Uri.parse("erimax://os/" + Uri.encode(osId) + "?action=recusar_transferencia"), this, MainActivity.class);
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