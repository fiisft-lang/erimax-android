import { normalNotificationRecipients } from "./notification-recipients.ts";

Deno.test("notificações normais incluem técnicos e somente o gestor Fii", () => {
  const recipients = normalNotificationRecipients([
    { id: "tec-1", nome: "Técnico 1", perfil: "tecnico" },
    { id: "fii", nome: "Fii", perfil: "gestor" },
    { id: "gestor-2", nome: "Outro gestor", perfil: "gestor" },
    { id: "operador", nome: "Operador", perfil: "operador" },
  ]);
  const ids = recipients.map((profile) => profile.id).sort();
  if (JSON.stringify(ids) !== JSON.stringify(["fii", "tec-1"])) {
    throw new Error("Destinatários inesperados: " + JSON.stringify(ids));
  }
});
