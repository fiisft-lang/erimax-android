import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
    const token = (req.headers.get('Authorization') || '').replace('Bearer ', '')
    const { data: { user } } = await admin.auth.getUser(token)
    if (!user) return json({ erro: 'Não autenticado.' }, 401)

    const { data: p } = await admin.from('perfis').select('perfil').eq('id', user.id).maybeSingle()
    if (p?.perfil !== 'gestor') return json({ erro: 'Apenas gestores podem gerenciar usuários.' }, 403)

    const body = await req.json()

    if (body.acao === 'senha') {
      if (!body.id || String(body.senha || '').length < 8)
        return json({ erro: 'Informe o usuário e uma senha de no mínimo 8 caracteres.' }, 400)
      const { error } = await admin.auth.admin.updateUserById(body.id, { password: body.senha })
      if (error) return json({ erro: error.message }, 400)
      return json({ ok: true })
    }

    if (body.acao === 'apagar') {
      if (!body.id) return json({ erro: 'Usuário não informado.' }, 400)
      if (body.id === user.id) return json({ erro: 'Você não pode apagar o seu próprio usuário.' }, 400)
      const { error } = await admin.auth.admin.deleteUser(body.id)
      if (error) return json({ erro: error.message }, 400)
      await admin.from('perfis').delete().eq('id', body.id)
      return json({ ok: true })
    }

    const { email, senha, nome, perfil } = body
    if (!email || !senha || !nome || !['operador', 'tecnico', 'gestor'].includes(perfil))
      return json({ erro: 'Preencha e-mail, nome, senha e perfil.' }, 400)
    if (String(senha).length < 8) return json({ erro: 'A senha precisa ter no mínimo 8 caracteres.' }, 400)

    const { data, error } = await admin.auth.admin.createUser({
      email, password: senha, email_confirm: true, user_metadata: { nome },
    })
    if (error) return json({ erro: error.message }, 400)

    await admin.from('perfis').upsert({ id: data.user.id, nome, email, perfil })
    return json({ ok: true })
  } catch (e) {
    return json({ erro: String(e) }, 500)
  }
})