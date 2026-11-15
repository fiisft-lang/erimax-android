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
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

public class IncomingCallActivity extends Activity {
  private String osId = "";

  @Override protected void onCreate(Bundle state) {
    super.onCreate(state);
    // Compatibilidade reforçada: mantém a Activity visível sobre a tela bloqueada
    // também em aparelhos que dependem das flags clássicas da janela.
    getWindow().addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
      | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
      | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    if (Build.VERSION.SDK_INT >= 27) {
      setShowWhenLocked(true);
      setTurnScreenOn(true);
    }
    // Evita forçar o modo de barras claras, que varia entre fabricantes/versões.
    // O conteúdo continua claro; as barras do sistema ficam no padrão anterior.
    getWindow().setStatusBarColor(Color.BLACK);
    getWindow().setNavigationBarColor(Color.BLACK);
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

    LinearLayout root = new LinearLayout(this);
    root.setOrientation(1);
    root.setGravity(Gravity.CENTER_HORIZONTAL);
    root.setPadding(dp(20), dp(28), dp(20), dp(24));
    android.graphics.drawable.GradientDrawable pageBg = new android.graphics.drawable.GradientDrawable(
      android.graphics.drawable.GradientDrawable.Orientation.TOP_BOTTOM,
      new int[]{Color.rgb(11, 31, 42), Color.rgb(16, 43, 58), Color.rgb(10, 27, 38)});
    root.setBackground(pageBg);

    TextView brand = label("ERIMAX  •  MANUTENÇÃO", 13, Color.rgb(242, 139, 0));
    brand.setTypeface(null, Typeface.BOLD);
    root.addView(brand, new LinearLayout.LayoutParams(-1, -2));

    TextView title = label(transferencia ? "Transferência de O.S." : "Nova ordem de serviço", 24, Color.WHITE);
    title.setTypeface(null, Typeface.BOLD);
    LinearLayout.LayoutParams titleParams = new LinearLayout.LayoutParams(-1, -2);
    titleParams.topMargin = dp(7);
    root.addView(title, titleParams);

    TextView status = label("AGUARDANDO SUA DECISÃO", 11, Color.rgb(255, 205, 128));
    status.setTypeface(null, Typeface.BOLD);
    android.graphics.drawable.GradientDrawable statusBg = new android.graphics.drawable.GradientDrawable();
    statusBg.setColor(Color.rgb(68, 54, 36));
    statusBg.setCornerRadius(dp(30));
    status.setBackground(statusBg);
    LinearLayout.LayoutParams statusParams = new LinearLayout.LayoutParams(-2, -2);
    statusParams.topMargin = dp(10);
    root.addView(status, statusParams);

    TextView intro = label(transferencia
      ? "Revise os dados antes de aceitar ou recusar a transferência."
      : "Uma nova solicitação de manutenção precisa da sua atenção.", 14, Color.rgb(190, 208, 216));
    LinearLayout.LayoutParams introParams = new LinearLayout.LayoutParams(-1, -2);
    introParams.topMargin = dp(10);
    root.addView(intro, introParams);

    LinearLayout infoCard = new LinearLayout(this);
    infoCard.setOrientation(1);
    infoCard.setPadding(dp(17), dp(8), dp(17), dp(8));
    android.graphics.drawable.GradientDrawable infoBg = new android.graphics.drawable.GradientDrawable();
    infoBg.setColor(Color.rgb(23, 57, 72));
    infoBg.setCornerRadius(dp(20));
    infoBg.setStroke(dp(1), Color.rgb(49, 86, 101));
    infoCard.setBackground(infoBg);
    LinearLayout.LayoutParams infoParams = new LinearLayout.LayoutParams(-1, -2);
    infoParams.setMargins(0, dp(20), 0, dp(12));
    root.addView(infoCard, infoParams);

    addInfoRow(infoCard, "ORDEM DE SERVIÇO", number == null ? "Nova O.S." : number);
    addInfoRow(infoCard, "SETOR", sector == null ? "Não informado" : sector);
    addInfoRow(infoCard, "MÁQUINA", machine == null ? "Não informada" : machine);
    addInfoRow(infoCard, "PROBLEMA INFORMADO",
      problem == null || problem.trim().isEmpty() ? "Não informado" : problem.trim());

    TextView actionHeading = label("TOQUE OU ARRASTE PARA CIMA PARA CONFIRMAR", 12, Color.rgb(190, 208, 216));
    actionHeading.setTypeface(null, Typeface.BOLD);
    LinearLayout.LayoutParams actionHeadingParams = new LinearLayout.LayoutParams(-1, -2);
    actionHeadingParams.topMargin = dp(8);
    root.addView(actionHeading, actionHeadingParams);
    LinearLayout actions = new LinearLayout(this);
    actions.setOrientation(0);
    actions.setGravity(Gravity.CENTER);
    actions.setPadding(0, dp(10), 0, 0);
    // Botões de toque direto: preservam exatamente os comandos já existentes.
    addActionButton(actions, transferencia ? "RECUSAR\nTRANSFERÊNCIA" : "SILENCIAR AVISO",
      Color.rgb(190, 65, 70), transferencia ? this::rejectTransfer : this::dismissCall);
    addActionButton(actions, transferencia ? "ACEITAR\nTRANSFERÊNCIA" : "ACEITAR O.S.",
      Color.rgb(22, 145, 94), this::answerCall);
    root.addView(actions);
    // A descrição pode ser longa e a altura útil muda conforme o aparelho.
    // ScrollView impede que os controles fiquem fora da tela ou sejam cortados.
    ScrollView scroll = new ScrollView(this);
    scroll.setFillViewport(true);
    scroll.setBackgroundColor(Color.rgb(11, 31, 42));
    scroll.setClipToPadding(false);
    scroll.addView(root, new ScrollView.LayoutParams(-1, -2));
    setContentView(scroll);
  }

  private void addInfoRow(LinearLayout card, String caption, String value) {
    TextView heading = label(caption, 10, Color.rgb(160, 188, 199));
    heading.setGravity(Gravity.LEFT | Gravity.CENTER_VERTICAL);
    heading.setTypeface(null, Typeface.BOLD);
    heading.setPadding(dp(2), dp(10), dp(2), 0);
    card.addView(heading, new LinearLayout.LayoutParams(-1, -2));

    TextView content = label(value, 16, Color.WHITE);
    content.setGravity(Gravity.LEFT | Gravity.CENTER_VERTICAL);
    content.setTypeface(null, Typeface.BOLD);
    content.setPadding(dp(2), dp(2), dp(2), dp(10));
    card.addView(content, new LinearLayout.LayoutParams(-1, -2));
  }

  private int dp(int value) {
    return (int)(value * getResources().getDisplayMetrics().density + 0.5f);
  }

  private void addActionButton(LinearLayout row, String text, int color, Runnable action) {
    TextView button = label(text, 14, Color.WHITE);
    button.setTypeface(null, Typeface.BOLD);
    button.setGravity(Gravity.CENTER);
    button.setMinHeight(dp(64));
    button.setPadding(dp(10), dp(14), dp(10), dp(14));
    android.graphics.drawable.GradientDrawable bg = new android.graphics.drawable.GradientDrawable();
    bg.setColor(color);
    bg.setCornerRadius(dp(16));
    bg.setStroke(dp(1), Color.argb(65, 255, 255, 255));
    button.setBackground(bg);
    button.setClickable(true);
    button.setFocusable(true);
    // Na tela bloqueada, tanto o toque quanto o gesto de arrastar para cima
    // disparam a mesma ação nativa. O comando segue para o app via deep link.
    final float[] inicioY = new float[]{0f};
    button.setOnTouchListener((v, event) -> {
      if (event.getAction() == MotionEvent.ACTION_DOWN) {
        inicioY[0] = event.getRawY();
        return true;
      }
      if (event.getAction() == MotionEvent.ACTION_UP) {
        action.run();
        return true;
      }
      return event.getAction() == MotionEvent.ACTION_MOVE;
    });
    button.setOnClickListener(v -> action.run());
    LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, -2, 1f);
    params.setMargins(dp(6), dp(4), dp(6), dp(4));
    row.addView(button, params);
  }

  private void stopAlarm() {
    IncomingCallMessagingService.stopAlert(this);
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

}