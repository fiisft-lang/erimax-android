/**
 * Destinatários de notificações normais: técnicos e o encarregado Fii.
 * Operadores e demais gestores ficam fora deste envio.
 */
export function normalNotificationRecipients<T extends { nome?: string; perfil?: string }>(profiles: T[]): T[] {
  return profiles.filter(p =>
    p.perfil === 'tecnico' || (p.nome === 'Fii' && p.perfil === 'gestor'))
}
