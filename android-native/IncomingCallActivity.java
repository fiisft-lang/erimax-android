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
import android.view.WindowManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

public class IncomingCallActivity extends Activity {
  private String osId = "";

  @Override protected void onCreate(Bundle state) {
    super.onCreate(state);
    if (Build.VERSION.SDK_INT >= 27) setShowWhenLocked(true);
    if (Build.VERSION.SDK_INT >= 27) setTurnScreenOn(true);
    getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    getWindow().setStatusBarColor(Color.rgb(9,37,65));
    getWindow().setNavigationBarColor(Color.rgb(9,37,65));
    osId = getIntent().getStringExtra("os_id");
    String machine = getIntent().getStringExtra("maquina");
    String sector = getIntent().getStringExtra("setor");
    String number = getIntent().getStringExtra("numero");
    IncomingCallMessagingService.startAlertAlarm(this);

    LinearLayout root = new LinearLayout(this);
    root.setOrientation(1); root.setGravity(Gravity.CENTER); root.setPadding(30,50,30,40);
    root.setBackgroundColor(Color.rgb(9,37,65));
    TextView brand = label("ERIMAX • MANUTENÇÃO",17,Color.LTGRAY);
    TextView title = label("Nova ordem de serviço",28,Color.WHITE); title.setTypeface(null,Typeface.BOLD);
    TextView detail = label((number == null ? "Nova O.S." : number) + "\n" + (machine == null ? "Máquina" : machine) + "\n" + (sector == null ? "Setor" : sector),21,Color.WHITE);
    root.addView(brand); root.addView(title); root.addView(detail); root.addView(label("Chamado aguardando atendimento",15,Color.LTGRAY));
    Button answer = new Button(this); answer.setText("ATENDER"); answer.setTextSize(18); answer.setOnClickListener(v -> answerCall());
    Button silence = new Button(this); silence.setText("SILENCIAR"); silence.setTextSize(16); silence.setOnClickListener(v -> dismissCall());
    LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(-1,-2); bp.setMargins(0,26,0,0);
    root.addView(answer,bp); root.addView(silence,bp); setContentView(root);
  }

  private void stopAlarm() {
    IncomingCallMessagingService.stopAlert();
  }

  private TextView label(String text,int size,int color) {
    TextView v = new TextView(this); v.setText(text); v.setTextSize(size); v.setTextColor(color); v.setGravity(Gravity.CENTER); v.setPadding(0,16,0,16); return v;
  }

  private void answerCall() {
    stopAlarm(); dismissNotification();
    Intent open = new Intent(Intent.ACTION_VIEW,Uri.parse("erimax://os/" + Uri.encode(osId)),this,MainActivity.class);
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