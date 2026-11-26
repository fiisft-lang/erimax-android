export function notificationRetryDelayMinutes(attempts: number): number {
  const normalized = Number.isFinite(attempts) ? Math.max(0, Math.trunc(attempts)) : 0
  return Math.min(30, Math.max(2, 2 ** Math.min(normalized + 1, 5)))
}
