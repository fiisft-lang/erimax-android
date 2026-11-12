import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { SignJWT, importPKCS8 } from 'https://esm.sh/jose@5'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

async function googleAccessToken(sa: { private_key: string; client_email: string }) {
  const key = await importPKCS8(sa.private_key, 'RS256')
  const assertion = await new SignJWT({ scope: 'https://www.googleapis.com/auth/firebase.messaging' })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(sa.client_email)
    .setAudience('https://oauth2.googleapis.com/token')
    .setIssuedAt()
    .setExpirationTime('55m')
    .sign(key)
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
  })
  const result = await response.json()
  if (!response.ok || !result.access_token) throw new Error('Falha na autenticação do Firebase.')
  return result.access_token as string
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ erro: 'Método não permitido.' }, 405)

  let osId: number | null = null
  let claimTime: string | null = null
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  try {
    const auth = req.headers.get('Authorization') || ''
    const jwt = auth.startsWith('Bearer ') ? auth.slice(7) : ''
    if (!jwt) return json({ erro: 'Não autenticado.' }, 401)

    // A plataforma já validou a assinatura deste JWT (verify_jwt=true).
    // Lemos apenas as claims autenticadas para evitar uma segunda validação remota.
    let claims: { sub?: string; role?: string }
    try {
      const part = jwt.split('.')[1]
      if (!part) throw new Error('JWT sem payload')
      const normalized = part.replace(/-/g, '+').replace(/_/g, '/')
      claims = JSON.parse(atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=')))
    } catch {
      return json({ erro: 'Sessão inválida.' }, 401)
    }
    if (claims.role !== 'authenticated' || typeof claims.sub !== 'string' || !claims.sub) {
      return json({ erro: 'Sessão inválida.' }, 401)
    }
    const user = { id: claims.sub }

    const { data: profile, error: profileError } = await admin.from('perfis')
      .select('perfil').eq('id', user.id).maybeSingle()
    if (profileError) throw profileError
    if (!profile || !['gestor', 'operador', 'tecnico'].includes(profile.perfil)) {
      return json({ erro: 'Seu perfil não pode disparar notificações de novas OS.' }, 403)
    }

    const body = await req.json().catch(() => ({}))
    osId = Number(body.os_id)
    if (!Number.isSafeInteger(osId) || osId <= 0) return json({ erro: 'Informe uma OS válida.' }, 400)

    const { data: os, error: osError } = await admin.from('os')
      .select('id,numero_mes,setor,maquina,prioridade,descricao,status,created_at,notificado_em')
      .eq('id', osId).maybeSingle()
    if (osError) throw osError
    if (!os) return json({ erro: 'OS não encontrada.' }, 404)
    if (os.notificado_em) return json({ ok: true, ja_enviado: true })
    if (os.status !== 'Aberta') return json({ erro: 'Somente OS aberta pode gerar chamado.' }, 400)
    if (!os.created_at || Date.now() - new Date(os.created_at).getTime() > 5 * 60 * 1000) {
      return json({ erro: 'OS fora da janela de envio de 5 minutos.' }, 400)
    }

    const { data: profiles, error: profilesError } = await admin.from('perfis')
      .select('id,perfil').in('perfil', ['tecnico', 'gestor', 'operador'])
    if (profilesError) throw profilesError

    const { data: onlineStatuses, error: statusError } = await admin.from('status_tecnicos')
      .select('user_id').eq('status', 'ONLINE').eq('turno_ativo', true)
    if (statusError) throw statusError
    const onlineIds = new Set((onlineStatuses || []).map((s: { user_id: string }) => s.user_id))
    const recipientIds = (profiles || [])
      // Somente Fii recebe aviso mesmo quando está EM SERVIÇO; os demais
      // técnicos, gestores e operadores precisam estar ONLINE e com turno ativo.
      .filter((p: { id: string; perfil: string }) => onlineIds.has(p.id))
      .map((p: { id: string }) => p.id)
    if (!recipientIds.length) return json({ ok: true, enviados: 0, aviso: 'Nenhum usuário ONLINE para receber a nova O.S.' })

    const { data: devices, error: devicesError } = await admin.from('dispositivos')
      .select('token').in('user_id', recipientIds)
    if (devicesError) throw devicesError
    const tokens = [...new Set((devices || []).map((d: { token: string }) => d.token).filter(Boolean))]
    if (!tokens.length) return json({ ok: true, enviados: 0, aviso: 'Nenhum celular registrado para receber notificações.' })

    const raw = Deno.env.get('FCM_SERVICE_ACCOUNT')
    if (!raw) throw new Error('Segredo FCM_SERVICE_ACCOUNT não configurado.')
    const sa = JSON.parse(raw)
    if (!sa.project_id || !sa.client_email || !sa.private_key) throw new Error('Segredo FCM_SERVICE_ACCOUNT inválido.')
    const access = await googleAccessToken(sa)

    claimTime = new Date().toISOString()
    const { data: claim, error: claimError } = await admin.from('os').update({ notificado_em: claimTime })
      .eq('id', osId).is('notificado_em', null).select('id').maybeSingle()
    if (claimError) throw claimError
    if (!claim) return json({ ok: true, ja_enviado: true })

    const numero = os.numero_mes ? String(os.numero_mes) : String(os.id)
    const data = {
      os_id: String(os.id),
      maquina: String(os.maquina || 'Manutenção'),
      setor: String(os.setor || 'Setor não informado'),
      numero: numero,
    }
    // Última conferência antes de enviar: exige expediente ativo.
    const { data: liveStatuses, error: liveStatusError } = await admin.from('status_tecnicos')
      .select('user_id').in('user_id', recipientIds).eq('status', 'ONLINE').eq('turno_ativo', true)
    if (liveStatusError) throw liveStatusError
    const liveIds = (liveStatuses || []).map((s: { user_id: string }) => s.user_id)
    const liveDeviceResult = liveIds.length ? await admin.from('dispositivos').select('token').in('user_id', liveIds) : { data: [], error: null }
    if (liveDeviceResult.error) throw liveDeviceResult.error
    const liveTokens = [...new Set((liveDeviceResult.data || []).map((d: { token: string }) => d.token).filter(Boolean))]
    if (!liveTokens.length) {
      await admin.from('os').update({ notificado_em: null }).eq('id', osId).eq('notificado_em', claimTime)
      claimTime = null
      return json({ ok: true, enviados: 0, aviso: 'Nenhum usuário continua com expediente ativo.' })
    }

    let enviados = 0
    const invalid: string[] = []
    const errors: string[] = []

    await Promise.all(liveTokens.map(async (deviceToken: string) => {
      const response = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${access}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: {
            token: deviceToken,
            android: { priority: 'HIGH', ttl: '15s' },
            data,
          },
        }),
      })
      if (response.ok) enviados++
      else {
        const details = await response.text()
        errors.push(details.slice(0, 350))
        if (/UNREGISTERED|NOT_FOUND/.test(details)) invalid.push(deviceToken)
      }
    }))

    if (invalid.length) await admin.from('dispositivos').delete().in('token', invalid)
    if (enviados === 0) {
      await admin.from('os').update({ notificado_em: null }).eq('id', osId).eq('notificado_em', claimTime)
      claimTime = null
      return json({ erro: 'O Firebase não aceitou nenhum envio.', detalhes: errors.slice(0, 2) }, 502)
    }
    return json({ ok: true, enviados, total_dispositivos: liveTokens.length })
  } catch (error) {
    if (claimTime !== null && osId !== null) {
      await admin.from('os').update({ notificado_em: null }).eq('id', osId).eq('notificado_em', claimTime)
    }
    console.error('Erro em notificar-os:', error)
    return json({ erro: 'Falha ao processar a notificação. Consulte os logs da função.' }, 500)
  }
})
