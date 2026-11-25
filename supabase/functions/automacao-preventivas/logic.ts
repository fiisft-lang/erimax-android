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

// Segunda a quarta: começa no próprio vencimento.
// Quinta a domingo: começa na quinta-feira daquela semana.
export function notificationStart(due: string) {
  const weekday = new Date(due + 'T12:00:00Z').getUTCDay()
  if (weekday >= 1 && weekday <= 3) return due
  const daysSinceThursday = weekday === 0 ? 3 : weekday - 4
  return addDays(due, -daysSinceThursday)
}

export function deadlineFor(start: string) {
  return new Date(addDays(start, 3) + 'T00:00:00-03:00').getTime() - 1000
}

export function machineRecords(p: any, machines: any[]) {
  const names = Array.isArray(p.maquinas) && p.maquinas.length
    ? p.maquinas.filter((x: unknown) => typeof x === 'string' && x.trim())
    : (p.maquina ? [p.maquina] : [])
  const ids = Array.isArray(p.maquinas_ids) ? p.maquinas_ids.map(Number) : []
  if (!names.length) return []
  if (ids.length === names.length && ids.every((id: number) => Number.isSafeInteger(id) && id > 0)) {
    return ids.map((id: number) => machines.find(m => Number(m.id) === id)).filter(Boolean)
  }
  return names.map((name: string) => {
    const matches = machines.filter(m => m.setor === p.setor && String(m.nome).trim() === String(name).trim())
    return matches.length === 1 ? matches[0] : null
  }).filter(Boolean)
}

export function uniqueTeam(p: any) {
  const list = (Array.isArray(p.tecnicos_participantes) ? p.tecnicos_participantes : [])
    .filter((x: unknown) => typeof x === 'string' && x.trim())
  if (typeof p.tecnico_responsavel === 'string' && p.tecnico_responsavel.trim()) list.push(p.tecnico_responsavel)
  return [...new Set(list)]
}
