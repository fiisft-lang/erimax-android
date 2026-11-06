import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ erro: "Método não permitido." }, 405);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  let claimedOsId: number | null = null;
  let claimTime: string | null = null;

  try {
    const auth = req.headers.get("Authorization") || "";
    const jwt = auth.startsWith("Bearer ") ? auth.slice(7) : "";
    if (!jwt) return json({ erro: "Não autenticado." }, 401);
    const { data: authData, error: authError } = await admin.auth.getUser(jwt);
    const user = authData?.user;
    if (authError || !user) return json({ erro: "Sessão inválida." }, 401);

    const { data: profile, error: profileError } = await admin.from("perfis")
      .select("perfil").eq("id", user.id).maybeSingle();
    if (profileError) throw profileError;
    if (!profile || !["gestor", "tecnico", "operador"].includes(profile.perfil)) {
      return json({ erro: "Perfil sem permissão para notificações." }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const action = String(body.action || "");

    if (action === "public_key") {
      const publicKey = Deno.env.get("VAPID_PUBLIC_KEY");
      if (!publicKey) return json({ erro: "Chave pública de notificações ainda não configurada." }, 503);
      return json({ public_key: publicKey });
    }

    if (action === "subscribe") {
      if (!["gestor", "tecnico"].includes(profile.perfil)) return json({ erro: "Somente manutenção pode ativar os avisos." }, 403);
      const sub = body.subscription;
      if (!sub?.endpoint || !sub?.keys?.p256dh || !sub?.keys?.auth) return json({ erro: "Assinatura inválida." }, 400);
      const { error } = await admin.from("web_push_subscriptions").upsert({
        user_id: user.id,
        endpoint: sub.endpoint,
        subscription: sub,
        user_agent: String(req.headers.get("user-agent") || "").slice(0, 500),
        updated_at: new Date().toISOString(),
      }, { onConflict: "endpoint" });
      if (error) throw error;
      return json({ ok: true });
    }

    if (action === "unsubscribe") {
      const endpoint = String(body.endpoint || "");
      if (!endpoint) return json({ erro: "Endpoint ausente." }, 400);
      const { error } = await admin.from("web_push_subscriptions").delete()
        .eq("user_id", user.id).eq("endpoint", endpoint);
      if (error) throw error;
      return json({ ok: true });
    }

    if (action !== "notify_os") return json({ erro: "Ação inválida." }, 400);
    const osId = Number(body.os_id);
    if (!Number.isSafeInteger(osId) || osId <= 0) return json({ erro: "Informe uma O.S. válida." }, 400);

    const { data: os, error: osError } = await admin.from("os")
      .select("id,numero_mes,setor,maquina,status,created_at,web_notificado_em")
      .eq("id", osId).maybeSingle();
    if (osError) throw osError;
    if (!os) return json({ erro: "O.S. não encontrada." }, 404);
    if (os.web_notificado_em) return json({ ok: true, ja_enviado: true });
    if (os.status !== "Aberta" || !os.created_at || Date.now() - new Date(os.created_at).getTime() > 5 * 60 * 1000) {
      return json({ erro: "O.S. fora da janela de envio." }, 400);
    }

    const { data: profiles, error: profilesError } = await admin.from("perfis")
      .select("id").in("perfil", ["tecnico", "gestor"]);
    if (profilesError) throw profilesError;
    const { data: statuses, error: statusesError } = await admin.from("status_tecnicos")
      .select("user_id").eq("status", "ONLINE").eq("turno_ativo", true);
    if (statusesError) throw statusesError;
    const online = new Set((statuses || []).map((s: { user_id: string }) => s.user_id));
    const recipientIds = (profiles || []).map((p: { id: string }) => p.id).filter((id: string) => online.has(id));
    if (!recipientIds.length) return json({ ok: true, enviados: 0, aviso: "Nenhum usuário ONLINE." });

    const { data: subscriptions, error: subError } = await admin.from("web_push_subscriptions")
      .select("id,endpoint,subscription").in("user_id", recipientIds);
    if (subError) throw subError;
    if (!subscriptions?.length) return json({ ok: true, enviados: 0, aviso: "Nenhum navegador registrado." });

    const publicKey = Deno.env.get("VAPID_PUBLIC_KEY") || "";
    const privateKey = Deno.env.get("VAPID_PRIVATE_KEY") || "";
    const subject = Deno.env.get("VAPID_SUBJECT") || "";
    if (!publicKey || !privateKey || !subject) return json({ erro: "Chaves VAPID ainda não configuradas." }, 503);
    webpush.setVapidDetails(subject, publicKey, privateKey);

    claimTime = new Date().toISOString();
    const { data: claim, error: claimError } = await admin.from("os")
      .update({ web_notificado_em: claimTime }).eq("id", osId).is("web_notificado_em", null).select("id").maybeSingle();
    if (claimError) throw claimError;
    if (!claim) return json({ ok: true, ja_enviado: true });
    claimedOsId = osId;

    const numero = os.numero_mes ? String(os.numero_mes) : String(os.id);
    const payload = JSON.stringify({
      title: "🚨 Nova O.S. aberta",
      body: "O.S. #" + numero + " • " + (os.setor || "Setor não informado") + " • " + (os.maquina || "Máquina não informada"),
      os_id: String(os.id),
      url: "/index.html?os=" + encodeURIComponent(String(os.id)),
      tag: "erimax-os-" + String(os.id),
    });
    let enviados = 0;
    const invalid: string[] = [];
    await Promise.all(subscriptions.map(async (item: { endpoint: string; subscription: unknown }) => {
      try {
        await webpush.sendNotification(item.subscription as webpush.PushSubscription, payload, { TTL: 120, urgency: "high" });
        enviados++;
      } catch (error) {
        const statusCode = Number((error as { statusCode?: number })?.statusCode || 0);
        if (statusCode === 404 || statusCode === 410) invalid.push(item.endpoint);
        console.error("Falha em Web Push:", statusCode || "erro");
      }
    }));
    if (invalid.length) await admin.from("web_push_subscriptions").delete().in("endpoint", invalid);
    if (!enviados) {
      await admin.from("os").update({ web_notificado_em: null }).eq("id", osId).eq("web_notificado_em", claimTime);
      claimedOsId = null;
      claimTime = null;
      return json({ ok: true, enviados: 0, aviso: "Nenhum navegador aceitou a notificação." });
    }
    return json({ ok: true, enviados });
  } catch (error) {
    if (claimedOsId !== null && claimTime !== null) {
      await admin.from("os").update({ web_notificado_em: null }).eq("id", claimedOsId).eq("web_notificado_em", claimTime);
    }
    console.error("Erro em webpush:", error);
    return json({ erro: "Falha ao processar Web Push." }, 500);
  }
});