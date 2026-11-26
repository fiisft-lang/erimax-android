export const TZ = 'America/Sao_Paulo'

export function localParts(date: Date) {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(date)
  return Object.fromEntries(parts.map(p => [p.type, p.value])) as Record<string, string>
}

export function addDays(iso: string, amount: number) {
  const d = new Date(iso + 'T12:00:00Z')
  d.setUTCDate(d.getUTCDate() + amount)
  return d.toISOString().slice(0, 10)
}

// Vencimentos de domingo são transferidos para segunda-feira e entram no ciclo de segunda a quarta.
// Vencimentos de segunda a quarta usam a janela fixa de segunda a quarta.
// Vencimentos de quinta a sábado usam a janela de quinta a sábado.
export function configuredReminderTimes(value: unknown): string[] {
  const defaults = ['08:00', '12:00', '16:00']
  if (!Array.isArray(value) || !value.length) return defaults
  return [...new Set(value.filter((h): h is string =>
    typeof h === 'string' && /^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(h) &&
    h >= '06:00' && h <= '22:45'
  ))].sort()
}

/**
 * Retorna todos os horários configurados que venceram nos últimos cinco minutos.
 * O slot usa o horário originalmente configurado para impedir duplicidade entre execuções.
 */
export function dueReminderSlots(times: string[], now: Date): { time: string; slotKey: string }[] {
  const parts = localParts(now)
  const today = `${parts.year}-${parts.month}-${parts.day}`
  const currentMinute = Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day), Number(parts.hour), Number(parts.minute)) / 60000
  return times.flatMap(time => {
    const [hour, minute] = time.split(':').map(Number)
    const targetMinute = Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day), hour, minute) / 60000
    const elapsed = currentMinute - targetMinute
    return elapsed >= 0 && elapsed < 5 ? [{ time, slotKey: today + '-' + time.replace(':', '') }] : []
  })
}

export function notificationStart(due: string): string {
  const weekday = new Date(due + 'T12:00:00Z').getUTCDay()
  if (weekday === 0) return addDays(due, 1)
  if (weekday >= 1 && weekday <= 3) return addDays(due, -(weekday - 1))
  return addDays(due, -(weekday - 4))
}

export function cycleEndExclusive(start: string) {
  return addDays(start, 3) + 'T00:00:00-03:00'
}

export function deadlineFor(start: string) {
  return new Date(cycleEndExclusive(start)).getTime() - 1000
}

export function machineRecords(p: any, machines: any[]) {
  const names = Array.isArray(p.maquinas) && p.maquinas.length
    ? p.maquinas.filter((x: unknown) => typeof x === 'string' && x.trim())
    : (p.maquina ? [p.maquina] : [])
  const ids = Array.isArray(p.maquinas_ids) ? p.maquinas_ids.map(Number) : []
  if (!names.length) return []
  if (ids.length === names.length && new Set(ids).size === ids.length && ids.every((id: number) => Number.isSafeInteger(id) && id > 0)) {
    return ids.map((id: number) => machines.find(m => Number(m.id) === id && m.setor === p.setor)).filter(Boolean)
  }
  return names.map((name: string) => {
    const matches = machines.filter(m => m.setor === p.setor && String(m.nome).trim() === String(name).trim())
    return matches.length === 1 ? matches[0] : null
  }).filter(Boolean)
}

/**
 * Técnicos da equipe recebem lembretes. Fii e Guilherme também são aceitos
 * como técnicos por seus IDs de dupla função; os demais gestores ficam fora.
 */
const DUAL_ROLE_TECH_IDS = new Set([
  'e978d5b1-9382-41de-be43-549a4e1e081e',
  'c1b96ae1-aa45-4563-83f6-a9cb33aa0a1c',
])

export function reminderRecipients(profiles: any[]) {
  return profiles.filter(p => p.perfil === 'tecnico' || DUAL_ROLE_TECH_IDS.has(String(p.id)))
}


export function uniqueTeam(p: any) {
  const list = (Array.isArray(p.tecnicos_participantes) ? p.tecnicos_participantes : [])
    .filter((x: unknown) => typeof x === 'string' && x.trim())
  if (typeof p.tecnico_responsavel === 'string' && p.tecnico_responsavel.trim()) list.push(p.tecnico_responsavel)
  return [...new Set(list)]
}
