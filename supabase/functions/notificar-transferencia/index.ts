import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "https://esm.sh/jose@5";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

async function googleAccessToken(sa: { private_key: string; client_email: string }) {
  const key = await importPKCS8(sa.private_key, "RS256");
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt()
    .setExpirationTime("55m")
    .sign(key);
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  const result = await response.json();
  if (!response.ok || !result.access_token) throw new Error("Falha na autenticação do Firebase.");
  return result.access_token as string;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ erro: "Método não permitido." }, 405);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const auth = req.headers.get("Authorization") || "";
    const jwt = auth.startsWith("Bearer ") ? auth.slice(7) : "";
    if (!jwt) return json({ erro: "Não autenticado." }, 401);

    let claims: { sub?: string; role?: string };
    try {
      const part = jwt.split(".")[1];
      if (!part) throw new Error("JWT sem payload");
      const normalized = part.replace(/-/g, "+").replace(/_/g, "/");
      claims = JSON.parse(atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=")));
    } catch {
      return json({ erro: "Sessão inválida." }, 401);
    }
    if (claims.role !== "authenticated" || typeof claims.sub !== "string" || !claims.sub) {
      return json({ erro: "Sessão inválida." }, 401);
    }

    const { data: solicitante, error: solicitanteError } = await admin.from("perfis")
      .select("id,nome,perfil").eq("id", claims.sub).maybeSingle();
    if (solicitanteError) throw solicitanteError;
    if (!solicitante || !["gestor", "tecnico"].includes(solicitante.perfil)) {
      return json({ erro: "Somente manutenção pode solicitar aviso de transferência." }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const osId = Number(body.os_id);
    if (!Number.isSafeInteger(osId) || osId <= 0) return json({ erro: "Informe uma O.S. válida." }, 400);

    const { data: os, error: osError } = await admin.from("os")
      .select("id,numero_mes,setor,maquina,status,tecnico,transferencia_para,transferencia_solicitada_em")
      .eq("id", osId).maybeSingle();
    if (osError) throw osError;
    if (!os || os.status !== "Em Atendimento" || !os.transferencia_para) {
      return json({ erro: "Não existe transferência aguardando aceite para esta O.S." }, 409);
    }
    if (solicitante.perfil === "tecnico" && os.tecnico !== solicitante.nome) {
      return json({ erro: "Somente o técnico responsável pode avisar esta transferência." }, 403);
    }

    const { data: destinatarios, error: destinatarioError } = await admin.from("perfis")
      .select("id,nome,perfil").eq("nome", os.transferencia_para);
    if (destinatarioError) throw destinatarioError;
    const destinatario = (destinatarios || []).find((p: { id: string; perfil: string }) =>
      p.perfil === "tecnico" || p.id === "e978d5b1-9382-41de-be43-549a4e1e081e"
    );
    if (!destinatario) return json({ erro: "O técnico destinatário não foi encontrado." }, 404);

    const { data: status, error: statusError } = await admin.from("status_tecnicos")
      .select("user_id,status,turno_ativo").eq("user_id", destinatario.id).maybeSingle();
    if (statusError) throw statusError;
    if (!status || status.status !== "ONLINE" || !status.turno_ativo) {
      return json({ ok: true, enviados: 0, aviso: "O destinatário está fora do expediente. A transferência continua aguardando aceite." });
    }

    const { data: devices, error: devicesError } = await admin.from("dispositivos")
      .select("token").eq("user_id", destinatario.id);
    if (devicesError) throw devicesError;
    const tokens = [...new Set((devices || []).map((d: { token: string }) => d.token).filter(Boolean))];
    if (!tokens.length) return json({ ok: true, enviados: 0, aviso: "O celular do destinatário ainda não está registrado para notificações." });

    const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
    if (!raw) throw new Error("Segredo FCM_SERVICE_ACCOUNT não configurado.");
    const sa = JSON.parse(raw);
    if (!sa.project_id || !sa.client_email || !sa.private_key) throw new Error("Segredo FCM_SERVICE_ACCOUNT inválido.");
    const access = await googleAccessToken(sa);

    // Revalida a transferência e o expediente imediatamente antes do envio.
    const [{ data: osAtual, error: osAtualError }, { data: statusAtual, error: statusAtualError }] = await Promise.all([
      admin.from("os").select("id,status,tecnico,transferencia_para").eq("id", osId).maybeSingle(),
      admin.from("status_tecnicos").select("user_id,status,turno_ativo").eq("user_id", destinatario.id).maybeSingle(),
    ]);
    if (osAtualError) throw osAtualError;
    if (statusAtualError) throw statusAtualError;
    if (!osAtual || osAtual.status !== "Em Atendimento" || osAtual.transferencia_para !== destinatario.nome ||
        !statusAtual || statusAtual.status !== "ONLINE" || !statusAtual.turno_ativo) {
      return json({ ok: true, enviados: 0, aviso: "A transferência ou o expediente mudou antes do envio." });
    }

    const numero = os.numero_mes ? String(os.numero_mes) : String(os.id);
    let enviados = 0;
    const invalid: string[] = [];
    const errors: string[] = [];
    await Promise.all(tokens.map(async (token: string) => {
      const response = await fetch("https://fcm.googleapis.com/v1/projects/" + sa.project_id + "/messages:send", {
        method: "POST",
        headers: { Authorization: "Bearer " + access, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token,
            notification: {
              title: "🔄 O.S. aguardando seu aceite",
              body: "O.S. #" + numero + " • " + (os.setor || "Setor não informado") + " • " + (os.maquina || "Máquina não informada"),
            },
            android: {
              priority: "HIGH",
              ttl: "15s",
              notification: { channel_id: "chamados", sound: "alarme" },
            },
            data: {
              acao: "transferencia_os",
              os_id: String(os.id),
              numero: numero,
              destinatario_id: String(destinatario.id),
            },
          },
        }),
      });
      if (response.ok) enviados++;
      else {
        const details = await response.text();
        errors.push(details.slice(0, 300));
        if (/UNREGISTERED|NOT_FOUND/.test(details)) invalid.push(token);
      }
    }));

    if (invalid.length) await admin.from("dispositivos").delete().in("token", invalid);
    if (!enviados) return json({ erro: "O Firebase não aceitou a notificação direcionada.", detalhes: errors.slice(0, 2) }, 502);
    return json({ ok: true, enviados, destinatario: destinatario.nome });
  } catch (error) {
    console.error("Erro em notificar-transferencia:", error);
    return json({ erro: "Falha ao enviar a notificação de transferência." }, 500);
  }
});
