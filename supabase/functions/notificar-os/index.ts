import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { SignJWT, importPKCS8 } from 'https://esm.sh/jose@5'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

async function tokenGoogle(sa: any) {
  const key = await importPKCS8(sa.private_key, 'RS256')
  const jwt = await new SignJWT({ scope: 'https://www.googleapis.com/auth/firebase.messaging' })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(sa.client_email)
    .setAudience('https://oauth2.googleapis.com/token')
    .setIssuedAt()
    .setExpirationTime('55m')
    .sign(key)
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: jwt }),
  })
  const j = await r.json()
  if (!j.access_token) throw new Error('Falha ao autenticar no Google: ' + JSON.stringify(j))
  return j.access_token as string
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
    const token = (req.headers.get('Authorization') || '').replace('Bearer ', '')
    const { data: { user } } = await admin.auth.getUser(token)
    if (!user) return json({ erro: 'Não autenticado.' }, 401)

    const { os_id } = await req.json()
    const { data: os } = await admin.from('os')
      .select('id,numero,setor,maquina,prioridade,descricao,created_at,notificado_em').eq('id', os_id).maybeSingle()
    if (!os) return json({ erro: 'OS não encontrada.' }, 404)
    if (os.notificado_em) return json({ ok: true, ja_enviado: true })
    if (Date.now() - new Date(os.created_at).getTime() > 5 * 60 * 1000)
      return json({ erro: 'OS antiga demais para notificar.' }, 400)
    await admin.from('os').update({ notificado_em: new Date().toISOString() }).eq('id', os.id)

    // quem recebe: técnicos e gestores
    const { data: alvo } = await admin.from('perfis').select('id').in('perfil', ['tecnico', 'gestor'])
    const { data: devs } = await admin.from('dispositivos').select('token').in('user_id', (alvo || []).map((x) => x.id))
    const tokens = (devs || []).map((d) => d.token)
    if (!tokens.length) return json({ ok: true, enviados: 0 })

    const sa = JSON.parse(Deno.env.get('FCM_SERVICE_ACCOUNT')!)
    const access = await tokenGoogle(sa)
    const titulo = `🚨 ${os.numero || 'Nova OS'} — ${os.maquina}`
    const corpo = `${os.setor} • Prioridade ${os.prioridade}\n${String(os.descricao || '').slice(0, 120)}`

    let enviados = 0
    const mortos: string[] = []
    await Promise.all(tokens.map(async (t) => {
      const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${access}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: {
            token: t,
            android: {
              priority: 'HIGH', ttl: '120s',
              notification: { channel_id: 'chamados', sound: 'alarme', notification_priority: 'PRIORITY_MAX', visibility: 'PUBLIC' },
            },
            data: { os_id: String(os.id), maquina: String(os.maquina || ''), setor: String(os.setor || ''), numero: String(os.numero || 'Nova O.S.') },
          },
        }),
      })
      if (r.ok) enviados++
      else {
        const e = JSON.stringify(await r.json().catch(() => ({})))
        if (/UNREGISTERED|NOT_FOUND/.test(e)) mortos.push(t)
      }
    }))
    if (mortos.length) await admin.from('dispositivos').delete().in('token', mortos)
    return json({ ok: true, enviados })
  } catch (e) {
    return json({ erro: String(e) }, 500)
  }
})
