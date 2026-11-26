import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { SignJWT, importPKCS8 } from 'https://esm.sh/jose@5'
import { normalNotificationRecipients } from '../_shared/notification-recipients.ts'
import { notificationRetryDelayMinutes } from '../_shared/notification-retry.ts'

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

type Delivery = {
  id: number
  os_id: number
  user_id: string
  tentativas: number
  status: string
  claim_em: string | null
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ erro: 'Método não permitido.' }, 405)

  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  try {
    const auth = req.headers.get('Authorization') || ''
    const jwt = auth.startsWith('Bearer ') ? auth.slice(7) : ''
    if (!jwt) return json({ erro: 'Não autenticado.' }, 401)

    // A plataforma valida a assinatura do JWT (verify_jwt=true); aqui lemos as claims autenticadas.
    let claims: { sub?: string; role?: string }
    try {
      const part = jwt.split('.')[1]
      if (!part) throw new Error('JWT sem payload')
      const normalized = part.replace(/-/g, '+').replace(/_/g, '/')
      claims = JSON.parse(atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=')))
    } catch {
      return json({ erro: 'Sessão inválida.' }, 401)
    }
    const serviceRole = claims.role === 'service_role'
    const authenticated = claims.role === 'authenticated' && typeof claims.sub === 'string' && !!claims.sub
    if (!serviceRole && !authenticated) return json({ erro: 'Sessão inválida.' }, 401)
    const userId = authenticated ? claims.sub! : null

    if (authenticated) {
      const { data: profile, error: profileError } = await admin.from('perfis')
        .select('perfil').eq('id', userId).maybeSingle()
      if (profileError) throw profileError
      if (!profile || !['gestor', 'operador', 'tecnico'].includes(profile.perfil)) {
        return json({ erro: 'Seu perfil não pode processar notificações de O.S.' }, 403)
      }
    }

    const body = await req.json().catch(() => ({}))
    if (body?.acao === 'reprocessar_todas_pendentes' && !serviceRole) {
      return json({ erro: 'Ação restrita ao serviço interno.' }, 403)
    }
    if (serviceRole && body?.acao !== 'reprocessar_todas_pendentes') {
      return json({ erro: 'A chave de serviço só pode reprocessar entregas pendentes.' }, 403)
    }
    if (!serviceRole && !authenticated) return json({ erro: 'Não autenticado.' }, 401)
    const now = new Date()
    const nowIso = now.toISOString()
    const stale = new Date(now.getTime() - 5 * 60 * 1000).toISOString()
    const raw = Deno.env.get('FCM_SERVICE_ACCOUNT')
    let sa: { project_id: string; client_email: string; private_key: string } | null = null
    let access: string | null = null
    const getAccess = async () => {
      if (!sa) {
        if (!raw) throw new Error('Segredo FCM_SERVICE_ACCOUNT não configurado.')
        const parsed = JSON.parse(raw) as { project_id: string; client_email: string; private_key: string }
        if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
          throw new Error('Segredo FCM_SERVICE_ACCOUNT inválido.')
        }
        sa = parsed
      }
      const serviceAccount = sa
      if (!serviceAccount) throw new Error('Segredo FCM_SERVICE_ACCOUNT inválido.')
      if (!access) access = await googleAccessToken(serviceAccount)
      return { sa: serviceAccount, access }
    }

    async function processDelivery(delivery: Delivery) {
      const { data: claim, error: claimError } = await admin.from('os_notificacao_entregas')
        .update({ status: 'processando', claim_em: nowIso, atualizado_em: nowIso })
        .eq('id', delivery.id)
        .in('status', ['pendente', 'processando'])
        .lte('proxima_tentativa_em', nowIso)
        .or('claim_em.is.null,claim_em.lt.' + stale)
        .select('id').maybeSingle()
      if (claimError) throw claimError
      if (!claim) return { enviados: 0, ignorada: true }

      const liberar = async (erro: string, atrasoMinutos = 5, contarTentativa = false) => {
        const update: Record<string, unknown> = {
          status: 'pendente',
          claim_em: null,
          proxima_tentativa_em: new Date(Date.now() + atrasoMinutos * 60 * 1000).toISOString(),
          ultimo_erro: erro.slice(0, 500),
          atualizado_em: new Date().toISOString(),
        }
        if (contarTentativa) update.tentativas = delivery.tentativas + 1
        const { error } = await admin.from('os_notificacao_entregas').update(update)
          .eq('id', delivery.id).eq('status', 'processando')
        if (error) throw error
      }

      try {
        const { data: os, error: osError } = await admin.from('os')
          .select('id,numero_mes,setor,maquina,descricao,status,notificado_em')
          .eq('id', delivery.os_id).maybeSingle()
        if (osError) throw osError
        if (!os || os.status !== 'Aberta') {
          const { error } = await admin.from('os_notificacao_entregas').update({
            status: 'dispensado', claim_em: null, atualizado_em: new Date().toISOString(),
            ultimo_erro: 'A O.S. não está mais aberta.',
          }).eq('id', delivery.id).eq('status', 'processando')
          if (error) throw error
          return { enviados: 0, dispensada: true }
        }

        const { data: status, error: statusError } = await admin.from('status_tecnicos')
          .select('user_id').eq('user_id', delivery.user_id)
          .in('status', ['ONLINE', 'EM SERVIÇO']).eq('turno_ativo', true).maybeSingle()
        if (statusError) throw statusError
        if (!status) {
          await liberar('Destinatário sem expediente ativo.')
          return { enviados: 0, aguardando: true }
        }

        const { data: devices, error: devicesError } = await admin.from('dispositivos')
          .select('token').eq('user_id', delivery.user_id)
        if (devicesError) throw devicesError
        const tokens = [...new Set((devices || []).map((d: { token: string }) => d.token).filter(Boolean))]
        if (!tokens.length) {
          await liberar('Nenhum celular registrado para o destinatário.')
          return { enviados: 0, aguardando: true }
        }

        const credentials = await getAccess()
        const results = await Promise.all(tokens.map(async (token: string) => {
          try {
            const response = await fetch(`https://fcm.googleapis.com/v1/projects/${credentials.sa.project_id}/messages:send`, {
              method: 'POST',
              headers: { Authorization: `Bearer ${credentials.access}`, 'Content-Type': 'application/json' },
              body: JSON.stringify({
                message: {
                  token,
                  android: { priority: 'HIGH', ttl: '15s' },
                  data: {
                    os_id: String(os.id),
                    maquina: String(os.maquina || 'Manutenção'),
                    setor: String(os.setor || 'Setor não informado'),
                    numero: String(os.numero_mes || os.id),
                    problema: String(os.descricao || 'Não informado'),
                  },
                },
              }),
            })
            if (response.ok) return { token, ok: true, error: '' }
            const details = await response.text()
            return { token, ok: false, error: details.slice(0, 350), invalid: /UNREGISTERED|NOT_FOUND/.test(details) }
          } catch (error) {
            return { token, ok: false, error: String(error).slice(0, 350) }
          }
        }))

        const invalid = results.filter(r => !r.ok && r.invalid).map(r => r.token)
        if (invalid.length) {
          const { error } = await admin.from('dispositivos').delete().in('token', invalid)
          if (error) throw error
        }
        const enviados = results.filter(r => r.ok).length
        if (enviados > 0) {
          const { error } = await admin.from('os_notificacao_entregas').update({
            status: 'enviado', enviado_em: new Date().toISOString(), claim_em: null,
            ultimo_erro: results.some(r => !r.ok) ? 'Entrega confirmada em pelo menos um dispositivo.' : null,
            atualizado_em: new Date().toISOString(),
          }).eq('id', delivery.id).eq('status', 'processando')
          if (error) throw error
          return { enviados }
        }

        const tentativa = delivery.tentativas + 1
        const espera = notificationRetryDelayMinutes(delivery.tentativas)
        const detalhe = results.map(r => r.error).filter(Boolean).slice(0, 2).join(' | ') || 'O Firebase não confirmou nenhum dispositivo.'
        await liberar(detalhe, espera, true)
        return { enviados: 0, falha: true }
      } catch (error) {
        await liberar(String(error), notificationRetryDelayMinutes(delivery.tentativas), true)
        throw error
      }
    }

    let deliveries: Delivery[] = []
    if (body?.acao === 'reprocessar_minhas' || body?.acao === 'reprocessar_todas_pendentes') {
      let query = admin.from('os_notificacao_entregas')
        .select('id,os_id,user_id,tentativas,status,claim_em')
        .in('status', ['pendente', 'processando'])
        .lte('proxima_tentativa_em', nowIso)
        .or('claim_em.is.null,claim_em.lt.' + stale)
        .order('criado_em', { ascending: true })
        .limit(serviceRole ? 100 : 20)
      if (!serviceRole) query = query.eq('user_id', userId)
      const { data, error } = await query
      if (error) throw error
      deliveries = (data || []) as Delivery[]
    } else {
      if (!authenticated) return json({ erro: 'Ação exige sessão de usuário.' }, 403)
      const osId = Number(body?.os_id)
      if (!Number.isSafeInteger(osId) || osId <= 0) return json({ erro: 'Informe uma O.S. válida.' }, 400)

      const { data: os, error: osError } = await admin.from('os')
        .select('id,numero_mes,setor,maquina,prioridade,descricao,status,created_at,notificado_em')
        .eq('id', osId).maybeSingle()
      if (osError) throw osError
      if (!os) return json({ erro: 'O.S. não encontrada.' }, 404)
      if (os.notificado_em) return json({ ok: true, ja_enviado: true })
      if (os.status !== 'Aberta') return json({ erro: 'Somente O.S. aberta pode gerar chamado.' }, 400)
      if (!os.created_at || Date.now() - new Date(os.created_at).getTime() > 5 * 60 * 1000) {
        return json({ erro: 'O.S. fora da janela inicial de envio de 5 minutos.' }, 400)
      }

      const { data: profiles, error: profilesError } = await admin.from('perfis')
        .select('id,nome,perfil').in('perfil', ['tecnico', 'gestor'])
      if (profilesError) throw profilesError
      const recipientIds = [...new Set(normalNotificationRecipients(profiles || []).map((p: { id: string }) => p.id))]
      if (!recipientIds.length) return json({ ok: true, enviados: 0, pendentes: 0, aviso: 'Nenhum destinatário habilitado para O.S. normal.' })

      const rows = recipientIds.map(id => ({ os_id: osId, user_id: id }))
      const { error: insertError } = await admin.from('os_notificacao_entregas')
        .upsert(rows, { onConflict: 'os_id,user_id', ignoreDuplicates: true })
      if (insertError) throw insertError

      const { data, error } = await admin.from('os_notificacao_entregas')
        .select('id,os_id,user_id,tentativas,status,claim_em')
        .eq('os_id', osId).in('status', ['pendente', 'processando'])
        .lte('proxima_tentativa_em', nowIso)
        .or('claim_em.is.null,claim_em.lt.' + stale)
      if (error) throw error
      deliveries = (data || []) as Delivery[]
    }

    let enviados = 0
    let falhas = 0
    for (const delivery of deliveries) {
      const result = await processDelivery(delivery)
      enviados += result.enviados
      if (result.falha) falhas++
    }

    const osIds = [...new Set(deliveries.map(d => d.os_id))]
    let pendentes = 0
    for (const id of osIds) {
      const { count, error } = await admin.from('os_notificacao_entregas')
        .select('id', { count: 'exact', head: true })
        .eq('os_id', id).in('status', ['pendente', 'processando'])
      if (error) throw error
      pendentes += count || 0
      if (!count) {
        await admin.from('os').update({ notificado_em: new Date().toISOString() })
          .eq('id', id).is('notificado_em', null)
      }
    }

    return json({
      ok: true, enviados, pendentes, destinatarios_processados: deliveries.length,
      ...(falhas ? { falhas } : {}),
    })
  } catch (error) {
    console.error('Erro em notificar-os:', error)
    return json({ erro: 'Falha ao processar notificações de O.S. Consulte os logs da função.' }, 500)
  }
})
