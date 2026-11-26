import { deadlineFor, localParts, machineRecords, notificationStart, reminderRecipients, normalNotificationRecipients, uniqueTeam } from './logic.ts'

function assertEquals(actual: unknown, expected: unknown, message: string) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(message + ': esperado ' + JSON.stringify(expected) + ', recebido ' + JSON.stringify(actual))
  }
}

Deno.test('janela começa no próprio dia para vencimentos de segunda a quarta', () => {
  assertEquals(notificationStart('2026-11-23'), '2026-11-23', 'segunda-feira')
  assertEquals(notificationStart('2026-11-24'), '2026-11-24', 'terça-feira')
  assertEquals(notificationStart('2026-11-25'), '2026-11-25', 'quarta-feira')
})

Deno.test('janela começa na quinta para vencimentos de quinta a domingo', () => {
  assertEquals(notificationStart('2026-11-26'), '2026-11-26', 'quinta-feira')
  assertEquals(notificationStart('2026-11-27'), '2026-11-26', 'sexta-feira')
  assertEquals(notificationStart('2026-11-28'), '2026-11-26', 'sábado')
  assertEquals(notificationStart('2026-11-29'), '2026-11-26', 'domingo')
})

Deno.test('prazo termina às 23:59:59 do terceiro dia local', () => {
  assertEquals(new Date(deadlineFor('2026-11-23')).toISOString(), '2026-11-26T02:59:59.000Z', 'ciclo segunda a quarta')
  assertEquals(new Date(deadlineFor('2026-11-26')).toISOString(), '2026-11-29T02:59:59.000Z', 'ciclo quinta a sábado')
})

Deno.test('horário local respeita America/Sao_Paulo', () => {
  const parts = localParts(new Date('2026-11-25T11:00:00.000Z'))
  assertEquals([parts.year, parts.month, parts.day, parts.hour, parts.minute], ['2026', '11', '25', '08', '00'], '08h de Brasília')
})

Deno.test('vínculo por id distingue máquinas com nomes iguais', () => {
  const result = machineRecords({
    setor: 'Corte',
    maquinas: ['Máquina 1', 'Máquina 1'],
    maquinas_ids: [10, 11],
  }, [
    { id: 10, nome: 'Máquina 1', prefixo: 'A', setor: 'Corte' },
    { id: 11, nome: 'Máquina 1', prefixo: 'B', setor: 'Corte' },
  ])
  assertEquals(result.map((m: any) => [m.id, m.prefixo]), [[10, 'A'], [11, 'B']], 'ids preservam identidade')
})

Deno.test('vínculo por nome não escolhe máquina ambígua', () => {
  const result = machineRecords({
    setor: 'Corte',
    maquinas: ['Máquina 1'],
    maquinas_ids: [],
  }, [
    { id: 10, nome: 'Máquina 1', prefixo: 'A', setor: 'Corte' },
    { id: 11, nome: 'Máquina 1', prefixo: 'B', setor: 'Corte' },
  ])
  assertEquals(result.length, 0, 'nome duplicado exige id')
})

Deno.test('equipe inclui responsável sem duplicar nomes', () => {
  assertEquals(uniqueTeam({
    tecnico_responsavel: 'Pedro',
    tecnicos_participantes: ['Marcelo', 'Pedro', 'Marcelo'],
  }), ['Marcelo', 'Pedro'], 'equipe sem duplicidade')
})

Deno.test('lembretes incluem técnicos e o encarregado Fii, mas não outros gestores', () => {
  const result = reminderRecipients([
    { id: '1', nome: 'Ana', perfil: 'tecnico' },
    { id: '2', nome: 'Fii', perfil: 'gestor' },
    { id: '3', nome: 'Outro gestor', perfil: 'gestor' },
    { id: '4', nome: 'Operador', perfil: 'operador' },
  ])
  assertEquals(result.map((p: any) => p.nome), ['Ana', 'Fii'], 'destinatários permitidos')
})

Deno.test('notificações normais de O.S. incluem Fii, mas não outros gestores nem operadores', () => {
  const result = normalNotificationRecipients([
    { id: '1', nome: 'Ana', perfil: 'tecnico' },
    { id: '2', nome: 'Fii', perfil: 'gestor' },
    { id: '3', nome: 'Outro gestor', perfil: 'gestor' },
    { id: '4', nome: 'Operador', perfil: 'operador' },
  ])
  assertEquals(result.map((p: any) => p.nome), ['Ana', 'Fii'], 'destinatários de novas O.S.')
})
