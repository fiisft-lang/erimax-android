import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { SignJWT, importPKCS8 } from 'https://esm.sh/jose@5'
import { TZ, localParts, notificationStart, deadlineFor, cycleEndExclusive, machineRecords, uniqueTeam } from './logic.ts'
import { normalNotificationRecipients } from '../_shared/notification-recipients.ts'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

function parseClaims(jwt: string) {
  const part = jwt.split('.')[1]
  if (!part) throw new Error('JWT sem payload')
  const normalized = part.replace(/-/g, '+').replace(/_/g, '/')
  return JSON.parse(atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '='))) as { role?: string }
}
async function googleAccessToken(sa: { private_key: string; client_email: string }) {
  const key = await importPKCS8(sa.private_key, 'RS256')
  const assertion = await new SignJWT({ scope: 'https://www.googleapis.com/auth/firebase.messaging' })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(sa.client_email)
    .setAudience('https://oauth2.googleapis.com/token')
    .setIssuedAt().setExpirationTime('55m').sign(key)
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
  })
  const result = await response.json()
  if (!response.ok || !result.access_token) throw new Error('Falha na autenticação do Firebase.')
  return result.access_token as string
}
async function sendFcm(tokens: string[], data: Record<string, string>, sa: any, access: string) {
  const invalid: string[] = []
  const delivered: string[] = []
  const errors: string[] = []
  await Promise.all(tokens.map(async token => {
    try {
      const response = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${access}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: { token, android: { priority: 'HIGH', ttl: '45s' }, data } }),
      })
      if (response.ok) delivered.push(token)
      else {
        const details = await response.text()
        errors.push(details.slice(0, 240))
        if (/UNREGISTERED|NOT_FOUND/.test(details)) invalid.push(token)
      }
    } catch (error) {
      // Preserva os tokens confirmados mesmo se outro envio falhar por rede.
      errors.push(String(error).slice(0, 240))
    }
  }))
  return { sent: delivered.length, delivered, invalid, errors }
}
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ erro: 'Método não permitido.' }, 405)

  try {
    const auth = req.headers.get('Authorization') || ''
    const jwt = auth.startsWith('Bearer ') ? auth.slice(7) : ''
    if (!jwt || parseClaims(jwt).role !== 'service_role') return json({ erro: 'Acesso restrito ao agendador.' }, 403)

    const url = Deno.env.get('SUPABASE_URL')
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    const raw = Deno.env.get('FCM_SERVICE_ACCOUNT')
    if (!url || !key || !raw) throw new Error('Configuração do Supabase ou Firebase ausente.')
    const admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })
    const sa = JSON.parse(raw)
    if (!sa.project_id || !sa.client_email || !sa.private_key) throw new Error('FCM_SERVICE_ACCOUNT inválido.')
    const now = new Date()
    const parts = localParts(now)
    const today = `${parts.year}-${parts.month}-${parts.day}`
    const hour = Number(parts.hour)
    const minute = Number(parts.minute)
    const slotHour = [8, 12, 16].includes(hour) ? hour : null
    const slotKey = slotHour === null ? null : `${today}-${String(slotHour).padStart(2, '0')}`
    const access = await googleAccessToken(sa)

    const [{ data: preventivas, error: prevError }, { data: machines, error: machineError }] = await Promise.all([
      admin.from('preventivas').select('id,setor,maquina,descricao,intervalo_dias,data_prevista,tecnico_responsavel,maquinas,tecnicos_participantes,maquinas_ids'),
      admin.from('maquinas').select('id,setor,nome,prefixo'),
    ])
    if (prevError) throw prevError
    if (machineError) throw machineError

    let geradas = 0
    let vinculadas = 0
    let ignoradas = 0
    for (const p of preventivas || []) {
      const due = String(p.data_prevista || '').slice(0, 10)
      if (!/^\d{4}-\d{2}-\d{2}$/.test(due)) continue
      const start = notificationStart(due)
      if (today < start) continue
      const records = machineRecords(p, machines || [])
      const names = (Array.isArray(p.maquinas) && p.maquinas.length ? p.maquinas : [p.maquina])
        .filter((x: unknown) => typeof x === 'string' && x.trim())
      if (!records.length || records.length !== names.length || records.some((m: any) => !m?.id)) {
        ignoradas++
        continue
      }
      const deadline = new Date(deadlineFor(start)).toISOString()
      const { data: inserted, error: insertError } = await admin.from('preventiva_execucoes')
        .upsert({
          preventiva_id: p.id, data_vencimento: due, data_geracao: start,
          prazo_em: deadline, status: 'aguardando',
        }, { onConflict: 'preventiva_id,data_vencimento', ignoreDuplicates: true })
        .select('*').maybeSingle()
      if (insertError) throw insertError
      let execution = inserted
      if (!execution) {
        const { data, error } = await admin.from('preventiva_execucoes').select('*')
          .eq('preventiva_id', p.id).eq('data_vencimento', due).maybeSingle()
        if (error) throw error
        execution = data
      }
      if (!execution) continue
      if (!execution.os_id) {
        // Recupera uma O.S. criada manualmente no mesmo ciclo ou por uma execução
        // que tenha sido interrompida depois do INSERT, antes de vincular o id.
        const cycleStart = start + 'T00:00:00-03:00'
        const { data: existingOS, error: existingError } = await admin.from('os').select('id,status')
          .eq('preventiva_id', p.id).gte('created_at', cycleStart).lt('created_at', cycleEndExclusive(start))
          .in('status', ['Aberta', 'Em Atendimento', 'Pausada', 'Concluída', 'Cancelada'])
          .order('id', { ascending: true }).limit(1).maybeSingle()
        if (existingError) throw existingError
        if (existingOS) {
          const status = existingOS.status === 'Concluída' ? 'concluida' : existingOS.status === 'Cancelada' ? 'cancelada' : 'aberta'
          const { error: prazoError } = await admin.from('os')
            .update({ prazo_preventiva_em: deadline }).eq('id', existingOS.id)
          if (prazoError) throw prazoError
          const { error } = await admin.from('preventiva_execucoes')
            .update({ os_id: existingOS.id, status, gerada_em: now.toISOString(), geracao_claim_em: null, atualizado_em: now.toISOString() })
            .eq('id', execution.id).is('os_id', null)
          if (error) throw error
          vinculadas++
        } else {
          const stale = new Date(now.getTime() - 5 * 60 * 1000).toISOString()
          let claim = await admin.from('preventiva_execucoes')
            .update({ status: 'gerando', geracao_claim_em: now.toISOString(), atualizado_em: now.toISOString() })
            .eq('id', execution.id).eq('status', 'aguardando').is('os_id', null).select('id').maybeSingle()
          if (claim.error) throw claim.error
          if (!claim.data) {
            claim = await admin.from('preventiva_execucoes')
              .update({ geracao_claim_em: now.toISOString(), atualizado_em: now.toISOString() })
              .eq('id', execution.id).eq('status', 'gerando').lt('geracao_claim_em', stale).is('os_id', null).select('id').maybeSingle()
            if (claim.error) throw claim.error
          }
          if (claim.data) {
            const h = Number(parts.hour)
            const team = uniqueTeam(p)
            const machineLabel = records.length > 1 ? records.length + ' máquinas do setor' : records[0].nome
            const machinesExecution = records.length > 1 ? records.map((m: any) => ({
              maquina_id: Number(m.id), nome: m.nome, prefixo: m.prefixo || null,
              concluida: false, concluida_em: null,
            })) : []
            const description = 'Preventiva: ' + p.descricao + (records.length > 1 ? '\nMáquinas: ' + records.map((m: any) => m.nome).join(', ') : '')
            const { data: os, error: osError } = await admin.from('os').insert([{
              preventiva_id: p.id,
              maquina_id: records.length === 1 ? Number(records[0].id) : null,
              turno: h < 14 ? 'Turno 1' : h < 22 ? 'Turno 2' : 'Turno 3',
              setor: p.setor,
              maquina: machineLabel,
              maquinas_execucao: machinesExecution,
              tecnicos_participantes: team,
              tipo: 'Preventiva',
              prioridade: 'Média',
              descricao: description,
              status: 'Aberta',
              tecnico: p.tecnico_responsavel || null,
              prazo_preventiva_em: deadline,
            }]).select('id').single()
            if (osError) {
              await admin.from('preventiva_execucoes').update({ status: 'aguardando', geracao_claim_em: null })
                .eq('id', execution.id).eq('status', 'gerando')
              throw osError
            }
            const { error: linkError } = await admin.from('preventiva_execucoes')
              .update({ os_id: os.id, gerada_em: now.toISOString(), status: 'aberta', geracao_claim_em: null, atualizado_em: now.toISOString() })
              .eq('id', execution.id).is('os_id', null)
            if (linkError) throw linkError
            geradas++
          }
        }
      }
    }

    let lembretes = 0
    let atrasadas = 0
    const { data: executions, error: execError } = await admin.from('preventiva_execucoes')
      .select('id,preventiva_id,data_vencimento,data_geracao,os_id,prazo_em,status,atraso_notificado_em,atraso_destinatarios,atraso_processando_em')
      .in('status', ['aberta', 'atrasada']).not('os_id', 'is', null)
    if (execError) throw execError

    for (const execution of executions || []) {
      const { data: os, error: osError } = await admin.from('os')
        .select('id,numero_mes,setor,maquina,descricao,status,tecnico,tecnicos_participantes,maquinas_execucao')
        .eq('id', execution.os_id).maybeSingle()
      if (osError) throw osError
      if (!os || os.status === 'Concluída' || os.status === 'Cancelada') continue

      if (now.getTime() > new Date(execution.prazo_em).getTime() && execution.status !== 'atrasada') {
        const { data: late, error: lateError } = await admin.from('preventiva_execucoes')
          .update({ status: 'atrasada', atualizado_em: now.toISOString() })
          .eq('id', execution.id).eq('status', 'aberta').select('id').maybeSingle()
        if (lateError) throw lateError
        if (late) {
          await admin.from('os').update({ preventiva_atrasada: true }).eq('id', os.id)
          execution.status = 'atrasada'
          atrasadas++
        }
      }

      const machinesLabel = Array.isArray(os.maquinas_execucao) && os.maquinas_execucao.length
        ? os.maquinas_execucao.map((m: any) => m.nome + (m.prefixo ? ' • ' + m.prefixo : '')).join(', ')
        : os.maquina
      const commonData = {
        os_id: String(os.id),
        maquina: String(os.maquina || 'Manutenção'),
        maquinas: String(machinesLabel || os.maquina || 'Não informadas'),
        setor: String(os.setor || 'Setor não informado'),
        numero: String(os.numero_mes || os.id),
        servico: String(os.descricao || 'Serviço preventivo').replace(/^Preventiva:\s*/, ''),
        prazo: new Intl.DateTimeFormat('pt-BR', { timeZone: TZ, dateStyle: 'short', timeStyle: 'short' })
          .format(new Date(execution.prazo_em)),
      }

      if (now.getTime() > new Date(execution.prazo_em).getTime()) {
        if (!execution.atraso_notificado_em) {
          const stale = new Date(now.getTime() - 5 * 60 * 1000).toISOString()
          const { data: claim, error: claimError } = await admin.from('preventiva_execucoes')
            .update({ atraso_processando_em: now.toISOString(), atualizado_em: now.toISOString() })
            .eq('id', execution.id).is('atraso_notificado_em', null)
            .or('atraso_processando_em.is.null,atraso_processando_em.lt.' + stale)
            .select('id').maybeSingle()
          if (claimError) throw claimError
          if (claim) {
            try {
              const { data: managers, error: managerError } = await admin.from('perfis').select('id').eq('perfil', 'gestor').eq('nome', 'Fii')
              if (managerError) throw managerError
              const managerIds = [...new Set((managers || []).map((p: any) => String(p.id)))]
              const { data: online, error: onlineError } = managerIds.length
                ? await admin.from('status_tecnicos').select('user_id').in('user_id', managerIds)
                    .in('status', ['ONLINE', 'EM SERVIÇO']).eq('turno_ativo', true)
                : { data: [], error: null }
              if (onlineError) throw onlineError
              const onlineIds = [...new Set((online || []).map((p: any) => String(p.user_id)))]
              const deliveredIds = Array.isArray(execution.atraso_destinatarios)
                ? execution.atraso_destinatarios.map(String) : []
              const pendingIds = onlineIds.filter((id: string) => !deliveredIds.includes(id))
              if (!onlineIds.length) {
                await admin.from('preventiva_execucoes').update({ atraso_processando_em: null })
                  .eq('id', execution.id).is('atraso_notificado_em', null)
              } else if (!pendingIds.length) {
                await admin.from('preventiva_execucoes').update({
                  atraso_notificado_em: now.toISOString(), atraso_processando_em: null,
                }).eq('id', execution.id).is('atraso_notificado_em', null)
              } else {
                const { data: devices, error: deviceError } = await admin.from('dispositivos')
                  .select('token,user_id').in('user_id', pendingIds)
                if (deviceError) throw deviceError
                const deviceRows = (devices || []).filter((d: any) => d.token && d.user_id)
                const tokens = [...new Set(deviceRows.map((d: any) => d.token))]
                if (!tokens.length) {
                  await admin.from('preventiva_execucoes').update({ atraso_processando_em: null })
                    .eq('id', execution.id).is('atraso_notificado_em', null)
                } else {
                  const result = await sendFcm(tokens, { ...commonData, tipo_alerta: 'preventiva_atrasada' }, sa, access)
                  if (result.invalid.length) await admin.from('dispositivos').delete().in('token', result.invalid)
                  const deliveredTokenSet = new Set(result.delivered)
                  const newlyDelivered = [...new Set(deviceRows
                    .filter((d: any) => deliveredTokenSet.has(d.token))
                    .map((d: any) => String(d.user_id)))]
                  const nextDelivered = [...new Set([...deliveredIds, ...newlyDelivered])]
                  const complete = onlineIds.every((id: string) => nextDelivered.includes(id))
                  const { error: saveError } = await admin.from('preventiva_execucoes').update({
                    atraso_destinatarios: nextDelivered,
                    atraso_notificado_em: complete ? now.toISOString() : null,
                    atraso_processando_em: null,
                    atualizado_em: now.toISOString(),
                  }).eq('id', execution.id).is('atraso_notificado_em', null)
                  if (saveError) throw saveError
                }
              }
            } catch (error) {
              await admin.from('preventiva_execucoes').update({ atraso_processando_em: null })
                .eq('id', execution.id).is('atraso_notificado_em', null)
              throw error
            }
          }
        }
        continue
      }

      if (slotKey && minute >= 0 && minute < 60) {
        // Fii é o encarregado gestor que participa da rotina preventiva e recebe
        // os lembretes normais; os demais gestores continuam fora deste envio.
        const teamNames = [...new Set([os.tecnico, ...(Array.isArray(os.tecnicos_participantes) ? os.tecnicos_participantes : []), 'Fii']
          .filter((x: unknown) => typeof x === 'string' && x.trim()))]
        if (!teamNames.length) continue
        const { data: profiles, error: profileError } = await admin.from('perfis')
          .select('id,nome,perfil').in('nome', teamNames)
        if (profileError) throw profileError
        const profileList = normalNotificationRecipients(profiles || [])
        const profileIds = profileList.map((p: any) => p.id)
        if (!profileIds.length) continue
        const { data: online, error: onlineError } = await admin.from('status_tecnicos')
          .select('user_id').in('user_id', profileIds).in('status', ['ONLINE', 'EM SERVIÇO']).eq('turno_ativo', true)
        if (onlineError) throw onlineError
        const onlineIds = (online || []).map((p: any) => p.user_id)
        if (!onlineIds.length) continue

        let claim: any = null
        let deliveredIds: string[] = []
        const { data: inserted, error: insertError } = await admin.from('preventiva_lembretes_enviados')
          .insert({ execucao_id: execution.id, slot_key: slotKey, horario: now.toISOString(), status: 'processando' })
          .select('id,destinatarios').maybeSingle()
        if (insertError && insertError.code !== '23505') throw insertError
        if (inserted) {
          claim = inserted
        } else {
          const { data: existing, error: existingError } = await admin.from('preventiva_lembretes_enviados')
            .select('id,status,horario,destinatarios').eq('execucao_id', execution.id).eq('slot_key', slotKey).maybeSingle()
          if (existingError) throw existingError
          if (!existing || existing.status === 'enviado') continue
          deliveredIds = Array.isArray(existing.destinatarios) ? existing.destinatarios.map(String) : []
          const stale = new Date(now.getTime() - 5 * 60 * 1000).toISOString()
          const reclaim = await admin.from('preventiva_lembretes_enviados')
            .update({ status: 'processando', horario: now.toISOString() })
            .eq('id', existing.id).eq('status', existing.status)
            .or(existing.status === 'parcial' ? 'status.eq.parcial' : 'horario.lt.' + stale)
            .select('id').maybeSingle()
          if (reclaim.error) throw reclaim.error
          if (!reclaim.data) continue
          claim = { id: existing.id }
        }
        if (!claim) continue

        try {
          const { data: live, error: liveError } = await admin.from('status_tecnicos')
            .select('user_id').in('user_id', onlineIds).in('status', ['ONLINE', 'EM SERVIÇO']).eq('turno_ativo', true)
          if (liveError) throw liveError
          const liveIds = [...new Set((live || []).map((p: any) => String(p.user_id)))]
          const pendingIds = liveIds.filter((id: string) => !deliveredIds.includes(id))
          if (!pendingIds.length) {
            // Se todos ficaram offline entre a primeira e a segunda consulta,
            // não marcar o horário como entregue: manter pendente para nova tentativa.
            await admin.from('preventiva_lembretes_enviados').update(liveIds.length
              ? { status: 'enviado', destinatarios: deliveredIds, enviado_em: now.toISOString() }
              : { status: 'parcial', destinatarios: deliveredIds, enviado_em: null }
            ).eq('id', claim.id).eq('status', 'processando')
            continue
          }
          const { data: devices, error: deviceError } = await admin.from('dispositivos')
            .select('token,user_id').in('user_id', pendingIds)
          if (deviceError) throw deviceError
          const deviceRows = (devices || []).filter((d: any) => d.token && d.user_id)
          const tokens = [...new Set(deviceRows.map((d: any) => d.token))]
          if (!tokens.length) {
            await admin.from('preventiva_lembretes_enviados').update({
              status: 'parcial', destinatarios: deliveredIds,
            }).eq('id', claim.id).eq('status', 'processando')
            continue
          }
          const result = await sendFcm(tokens, { ...commonData, tipo_alerta: 'preventiva_lembrete' }, sa, access)
          if (result.invalid.length) await admin.from('dispositivos').delete().in('token', result.invalid)
          const deliveredTokenSet = new Set(result.delivered)
          const newlyDelivered = [...new Set(deviceRows
            .filter((d: any) => deliveredTokenSet.has(d.token))
            .map((d: any) => String(d.user_id)))]
          deliveredIds = [...new Set([...deliveredIds, ...newlyDelivered])]
          const complete = liveIds.every((id: string) => deliveredIds.includes(id))
          const { error: saveError } = await admin.from('preventiva_lembretes_enviados').update({
            status: complete ? 'enviado' : 'parcial',
            destinatarios: deliveredIds,
            enviado_em: complete ? now.toISOString() : null,
          }).eq('id', claim.id).eq('status', 'processando')
          if (saveError) throw saveError
          lembretes += result.sent
        } catch (error) {
          await admin.from('preventiva_lembretes_enviados').update({ status: 'parcial' })
            .eq('id', claim.id).eq('status', 'processando')
          throw error
        }
      }
    }

    return json({ ok: true, data_local: today, hora_local: parts.hour + ':' + parts.minute, geradas, vinculadas, ignoradas, lembretes, atrasadas })
  } catch (error) {
    console.error('Erro em automacao-preventivas:', error)
    return json({ erro: 'Falha ao processar automação de preventivas.', detalhe: String(error) }, 500)
  }
})
