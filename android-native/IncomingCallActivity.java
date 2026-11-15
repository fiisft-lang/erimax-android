package com.webapp.erimaxmanuteno;

import android.app.Activity;
import android.app.NotificationManager;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.LinearLayout;
import android.widget.FrameLayout;
import android.widget.ScrollView;
import android.widget.TextView;

public class IncomingCallActivity extends Activity {
  private static final int NAVY = Color.rgb(8, 25, 37);
  private static final int PANEL = Color.rgb(17, 43, 58);
  private static final int PANEL_LIGHT = Color.rgb(23, 55, 72);
  private static final int BORDER = Color.rgb(47, 83, 101);
  private static final int SOFT_BORDER = Color.rgb(34, 66, 82);
  private static final int MUTED = Color.rgb(169, 194, 205);
  private static final int ACCENT = Color.rgb(255, 164, 66);
  private String osId = "";

  @Override protected void onCreate(Bundle state) {
    super.onCreate(state);
    getWindow().addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
      | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
      | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    if (Build.VERSION.SDK_INT >= 27) {
      setShowWhenLocked(true);
      setTurnScreenOn(true);
    }
    getWindow().setStatusBarColor(NAVY);
    getWindow().setNavigationBarColor(NAVY);
    getWindow().getDecorView().setSystemUiVisibility(0);

    osId = getIntent().getStringExtra("os_id");
    if (osId == null) osId = "";
    String notificationAction = getIntent().getStringExtra("notification_action");
    if ("silenciar".equals(notificationAction)) { dismissCall(); return; }
    if ("recusar_transferencia".equals(notificationAction)) { rejectTransfer(); return; }
    if ("assumir".equals(notificationAction) || "aceitar_transferencia".equals(notificationAction)) { answerCall(); return; }

    boolean transferencia = "transferencia_os".equals(getIntent().getStringExtra("acao"));
    String machine = safe(getIntent().getStringExtra("maquina"), "Não informada");
    String sector = safe(getIntent().getStringExtra("setor"), "Não informado");
    String number = safe(getIntent().getStringExtra("numero"), "Nova O.S.");
    String problem = safe(getIntent().getStringExtra("problema"), "Não informado");

    LinearLayout root = new LinearLayout(this);
    root.setOrientation(LinearLayout.VERTICAL);
    root.setGravity(Gravity.CENTER_HORIZONTAL);
    root.setPadding(dp(22), dp(22), dp(22), dp(20));
    GradientDrawable background = new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
      new int[]{Color.rgb(7, 24, 36), Color.rgb(13, 39, 54), Color.rgb(8, 27, 40)});
    root.setBackground(background);

    LinearLayout brandRow = new LinearLayout(this);
    brandRow.setOrientation(LinearLayout.HORIZONTAL);
    brandRow.setGravity(Gravity.CENTER_VERTICAL);
    GradientDrawable brandBg = rounded(Color.rgb(19, 49, 65), dp(22), Color.rgb(47, 83, 101));
    brandRow.setBackground(brandBg);
    brandRow.setPadding(dp(14), dp(6), dp(15), dp(6));
    brandRow.setElevation(dp(3));
    TextView brandMark = label("E", 15, NAVY);
    brandMark.setTypeface(null, Typeface.BOLD);
    GradientDrawable markBg = new GradientDrawable();
    markBg.setColor(ACCENT);
    markBg.setShape(GradientDrawable.OVAL);
    brandMark.setBackground(markBg);
    brandMark.setPadding(0, 0, 0, 0);
    brandMark.setElevation(dp(2));
    brandRow.addView(brandMark, new LinearLayout.LayoutParams(dp(27), dp(27)));
    TextView brand = label("ERIMAX  /  MANUTENÇÃO", 11, Color.WHITE);
    brand.setTypeface(null, Typeface.BOLD);
    brand.setGravity(Gravity.CENTER_VERTICAL);
    brand.setPadding(dp(9), 0, 0, 0);
    brandRow.addView(brand);
    root.addView(brandRow);

    TextView eyebrow = label(transferencia ? "AÇÃO NECESSÁRIA" : "ALERTA DE MANUTENÇÃO", 10, ACCENT);
    eyebrow.setTypeface(null, Typeface.BOLD);
    eyebrow.setLetterSpacing(0.12f);
    LinearLayout.LayoutParams eyebrowParams = new LinearLayout.LayoutParams(-1, -2);
    eyebrowParams.topMargin = dp(28);
    root.addView(eyebrow, eyebrowParams);

    TextView title = label(transferencia ? "Transferência de O.S." : "Nova ordem de serviço", 25, Color.WHITE);
    title.setTypeface(null, Typeface.BOLD);
    title.setGravity(Gravity.CENTER);
    title.setPadding(dp(2), dp(7), dp(2), dp(4));
    title.setLetterSpacing(-0.02f);
    root.addView(title, new LinearLayout.LayoutParams(-1, -2));

    TextView subtitle = label(transferencia
      ? "Uma ordem de serviço foi direcionada para você."
      : "Uma nova ocorrência precisa da sua atenção.", 13, MUTED);
    subtitle.setGravity(Gravity.CENTER);
    subtitle.setPadding(dp(8), dp(3), dp(8), dp(20));
    root.addView(subtitle, new LinearLayout.LayoutParams(-1, -2));

    LinearLayout infoCard = new LinearLayout(this);
    infoCard.setOrientation(LinearLayout.VERTICAL);
    infoCard.setPadding(dp(17), dp(16), dp(17), dp(12));
    infoCard.setBackground(rounded(PANEL, dp(19), BORDER));
    infoCard.setElevation(dp(7));

    TextView osLabel = label("ORDEM DE SERVIÇO", 10, MUTED);
    osLabel.setTypeface(null, Typeface.BOLD);
    osLabel.setGravity(Gravity.LEFT | Gravity.CENTER_VERTICAL);
    infoCard.addView(osLabel);

    TextView osNumber = label(number, 21, Color.WHITE);
    osNumber.setTypeface(null, Typeface.BOLD);
    osNumber.setGravity(Gravity.LEFT | Gravity.CENTER_VERTICAL);
    osNumber.setPadding(dp(11), dp(7), dp(11), dp(7));
    osNumber.setBackground(rounded(PANEL_LIGHT, dp(11), SOFT_BORDER));
    LinearLayout.LayoutParams numberParams = new LinearLayout.LayoutParams(-1, -2);
    numberParams.topMargin = dp(5);
    numberParams.bottomMargin = dp(8);
    infoCard.addView(osNumber, numberParams);

    addInfoRow(infoCard, "SETOR", sector, "▦");
    addInfoRow(infoCard, "MÁQUINA", machine, "⚙");
    addInfoRow(infoCard, "PROBLEMA INFORMADO", problem, "!");
    LinearLayout.LayoutParams cardParams = new LinearLayout.LayoutParams(-1, -2);
    cardParams.setMargins(0, 0, 0, dp(16));
    root.addView(infoCard, cardParams);

    TextView instruction = label("ESCOLHA UMA AÇÃO", 10, MUTED);
    instruction.setTypeface(null, Typeface.BOLD);
    instruction.setLetterSpacing(0.08f);
    root.addView(instruction, new LinearLayout.LayoutParams(-1, dp(30)));

    LinearLayout actions = new LinearLayout(this);
    actions.setOrientation(LinearLayout.HORIZONTAL);
    actions.setGravity(Gravity.CENTER);
    actions.setPadding(0, dp(3), 0, 0);
    addSwipeAction(actions, transferencia ? "RECUSAR" : "SILENCIAR",
      transferencia ? "×" : "−", Color.rgb(218, 75, 77),
      transferencia ? this::rejectTransfer : this::dismissCall);
    addSwipeAction(actions, transferencia ? "ACEITAR" : "ASSUMIR O.S.",
      "✓", Color.rgb(25, 171, 111), this::answerCall);
    root.addView(actions, new LinearLayout.LayoutParams(-1, -2));

    TextView footer = label("Deslize o controle para cima para confirmar.", 11, Color.rgb(150, 177, 190));
    footer.setGravity(Gravity.CENTER);
    footer.setPadding(dp(8), dp(16), dp(8), 0);
    root.addView(footer, new LinearLayout.LayoutParams(-1, -2));

    ScrollView scroll = new ScrollView(this);
    scroll.setFillViewport(true);
    scroll.setClipToPadding(false);
    scroll.addView(root, new ScrollView.LayoutParams(-1, -2));
    setContentView(scroll);
  }

  @Override protected void onNewIntent(Intent intent) {
    super.onNewIntent(intent);
    setIntent(intent);
    String notificationAction = intent.getStringExtra("notification_action");
    if ("silenciar".equals(notificationAction)) {
      dismissCall();
    } else if ("recusar_transferencia".equals(notificationAction)) {
      rejectTransfer();
    } else if ("assumir".equals(notificationAction) || "aceitar_transferencia".equals(notificationAction)) {
      answerCall();
    } else {
      recreate();
    }
  }

  private String safe(String value, String fallback) {
    return value == null || value.trim().isEmpty() ? fallback : value.trim();
  }

  private GradientDrawable rounded(int color, int radius, int stroke) {
    GradientDrawable shape = new GradientDrawable();
    shape.setColor(color);
    shape.setCornerRadius(radius);
    shape.setStroke(dp(1), stroke);
    return shape;
  }

  private void addInfoRow(LinearLayout card, String caption, String value, String symbol) {
    LinearLayout row = new LinearLayout(this);
    row.setOrientation(LinearLayout.HORIZONTAL);
    row.setGravity(Gravity.CENTER_VERTICAL);
    row.setPadding(0, dp(10), 0, dp(10));

    TextView icon = label(symbol, 17, ACCENT);
    icon.setTypeface(null, Typeface.BOLD);
    GradientDrawable iconBg = rounded(PANEL_LIGHT, dp(11), BORDER);
    icon.setBackground(iconBg);
    row.addView(icon, new LinearLayout.LayoutParams(dp(38), dp(38)));

    LinearLayout texts = new LinearLayout(this);
    texts.setOrientation(LinearLayout.VERTICAL);
    texts.setPadding(dp(12), 0, 0, 0);
    TextView heading = label(caption, 9, MUTED);
    heading.setTypeface(null, Typeface.BOLD);
    heading.setGravity(Gravity.LEFT | Gravity.CENTER_VERTICAL);
    heading.setLetterSpacing(0.08f);
    TextView content = label(value, 14, Color.WHITE);
    content.setTypeface(null, Typeface.BOLD);
    content.setGravity(Gravity.LEFT | Gravity.CENTER_VERTICAL);
    content.setPadding(0, dp(2), 0, 0);
    texts.addView(heading);
    texts.addView(content);
    row.addView(texts, new LinearLayout.LayoutParams(0, -2, 1f));
    card.addView(row);
    if (!"PROBLEMA INFORMADO".equals(caption)) {
      View divider = new View(this);
      divider.setBackgroundColor(SOFT_BORDER);
      LinearLayout.LayoutParams dividerParams = new LinearLayout.LayoutParams(-1, dp(1));
      dividerParams.leftMargin = dp(50);
      card.addView(divider, dividerParams);
    }
  }

  private int dp(int value) {
    return (int)(value * getResources().getDisplayMetrics().density + 0.5f);
  }

  private void addSwipeAction(LinearLayout row, String hint, String symbol, int color, Runnable action) {
    LinearLayout item = new LinearLayout(this);
    item.setOrientation(LinearLayout.VERTICAL);
    item.setGravity(Gravity.CENTER_HORIZONTAL);
    GradientDrawable itemBg = rounded(Color.rgb(15, 39, 53), dp(20), BORDER);
    item.setBackground(itemBg);
    item.setPadding(dp(8), dp(13), dp(8), dp(11));
    item.setElevation(dp(2));
    LinearLayout.LayoutParams itemParams = new LinearLayout.LayoutParams(0, -2, 1f);
    itemParams.setMargins(dp(6), 0, dp(6), 0);

    TextView title = label(hint, 11, Color.WHITE);
    title.setTypeface(null, Typeface.BOLD);
    title.setMaxLines(1);
    title.setLetterSpacing(0.025f);
    item.addView(title, new LinearLayout.LayoutParams(-1, dp(28)));

    FrameLayout track = new FrameLayout(this);
    GradientDrawable trackBg = new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
      new int[]{Color.rgb(29, 66, 84), Color.rgb(15, 40, 55)});
    trackBg.setCornerRadius(dp(34));
    trackBg.setStroke(dp(1), Color.rgb(66, 104, 122));
    track.setBackground(trackBg);
    LinearLayout.LayoutParams trackParams = new LinearLayout.LayoutParams(dp(82), dp(132));
    trackParams.gravity = Gravity.CENTER_HORIZONTAL;
    trackParams.topMargin = dp(6);

    TextView hintView = label("↑", 20, ACCENT);
    hintView.setTypeface(null, Typeface.BOLD);
    FrameLayout.LayoutParams hintParams = new FrameLayout.LayoutParams(-1, dp(43), Gravity.TOP);
    hintView.setAlpha(0.9f);
    track.addView(hintView, hintParams);

    TextView thumb = label(symbol, 25, Color.WHITE);
    thumb.setTypeface(null, Typeface.BOLD);
    GradientDrawable thumbBg = new GradientDrawable();
    thumbBg.setColor(color);
    thumbBg.setShape(GradientDrawable.OVAL);
    thumbBg.setStroke(dp(3), Color.rgb(219, 235, 240));
    thumb.setBackground(thumbBg);
    thumb.setElevation(dp(5));
    FrameLayout.LayoutParams thumbParams = new FrameLayout.LayoutParams(dp(62), dp(62), Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
    thumbParams.bottomMargin = dp(5);
    track.addView(thumb, thumbParams);

    final float[] downY = {0};
    final float[] startY = {0};
    thumb.setContentDescription("Arraste para cima: " + hint);
    thumb.setOnTouchListener((View v, MotionEvent event) -> {
      float max = Math.max(0, track.getHeight() - thumb.getHeight() - dp(10));
      switch (event.getAction()) {
        case MotionEvent.ACTION_DOWN:
          downY[0] = event.getRawY();
          startY[0] = thumb.getTranslationY();
          thumb.animate().scaleX(1.06f).scaleY(1.06f).setDuration(100).start();
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
          thumb.animate().scaleX(1f).scaleY(1f).setDuration(100).start();
          if (event.getAction() == MotionEvent.ACTION_UP && moved >= max * 0.62f) {
            action.run();
          } else {
            thumb.animate().translationY(0).setDuration(190).start();
          }
          return true;
      }
      return true;
    });
    item.addView(track, trackParams);
    TextView instruction = label("PUXE PARA ATIVAR", 8, MUTED);
    instruction.setTypeface(null, Typeface.BOLD);
    instruction.setLetterSpacing(0.04f);
    instruction.setPadding(0, dp(8), 0, 0);
    item.addView(instruction, new LinearLayout.LayoutParams(-1, dp(25)));
    row.addView(item, itemParams);
  }

  private void stopAlarm() {
    IncomingCallMessagingService.stopAlert(this);
  }

  private TextView label(String text, int size, int color) {
    TextView v = new TextView(this);
    v.setText(text);
    v.setTextSize(size);
    v.setTextColor(color);
    v.setGravity(Gravity.CENTER);
    v.setPadding(dp(6), dp(5), dp(6), dp(5));
    return v;
  }

  private void answerCall() {
    stopAlarm(); dismissNotification();
    String action = "transferencia_os".equals(getIntent().getStringExtra("acao")) ? "aceitar_transferencia" : "assumir";
    Intent open = new Intent(Intent.ACTION_VIEW, Uri.parse("erimax://os/" + Uri.encode(osId) + "?action=" + action), this, MainActivity.class);
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
