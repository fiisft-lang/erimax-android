import { notificationRetryDelayMinutes } from '../_shared/notification-retry.ts'

Deno.test('primeira falha agenda nova tentativa em 2 minutos', () => {
  if (notificationRetryDelayMinutes(0) !== 2) throw new Error('A primeira espera deve ser 2 minutos.')
})

Deno.test('intervalo cresce progressivamente sem ultrapassar 30 minutos', () => {
  const actual = [0, 1, 2, 3, 4, 8].map(notificationRetryDelayMinutes)
  const expected = [2, 4, 8, 16, 30, 30]
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error('Intervalos inesperados: ' + JSON.stringify(actual))
  }
})

Deno.test('tentativas inválidas usam intervalo mínimo seguro', () => {
  if (notificationRetryDelayMinutes(-10) !== 2) throw new Error('Tentativa negativa não deve reduzir a espera.')
  if (notificationRetryDelayMinutes(Number.NaN) !== 2) throw new Error('Tentativa inválida não deve quebrar o cálculo.')
})
