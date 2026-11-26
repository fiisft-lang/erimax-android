import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ erro: 'Método não permitido.' }, 405)

  try {
    const url = Deno.env.get('SUPABASE_URL')
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!url || !serviceKey) throw new Error('Configuração administrativa indisponível.')

    const authHeader = req.headers.get('Authorization') || ''
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7).trim() : ''
    if (!token) return json({ erro: 'Não autenticado.' }, 401)

    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: { user }, error: authError } = await admin.auth.getUser(token)
    if (authError || !user) return json({ erro: 'Sessão inválida ou expirada.' }, 401)

    const { data: profile, error: profileError } = await admin.from('perfis')
      .select('perfil').eq('id', user.id).maybeSingle()
    if (profileError) throw profileError
    if (profile?.perfil !== 'gestor') return json({ erro: 'Apenas gestores podem gerenciar usuários.' }, 403)

    const body = await req.json().catch(() => null)
    if (!body || typeof body !== 'object' || Array.isArray(body))
      return json({ erro: 'Dados da solicitação inválidos.' }, 400)

    if (body.acao === 'senha') {
      const id = String(body.id || '').trim()
      const senha = String(body.senha || '')
      if (!id || senha.length < 8)
        return json({ erro: 'Informe o usuário e uma senha de no mínimo 8 caracteres.' }, 400)
      const { error } = await admin.auth.admin.updateUserById(id, { password: senha })
      if (error) return json({ erro: error.message }, 400)
      return json({ ok: true })
    }

    if (body.acao === 'apagar') {
      const id = String(body.id || '').trim()
      if (!id) return json({ erro: 'Usuário não informado.' }, 400)
      if (id === user.id) return json({ erro: 'Você não pode apagar o seu próprio usuário.' }, 400)

      const { error: deleteAuthError } = await admin.auth.admin.deleteUser(id)
      if (deleteAuthError) return json({ erro: deleteAuthError.message }, 400)

      // A FK de perfis normalmente remove o registro em cascata. A limpeza
      // explícita cobre projetos sem cascade; qualquer erro fica visível.
      const { error: deleteProfileError } = await admin.from('perfis').delete().eq('id', id)
      if (deleteProfileError) {
        console.error('Usuário removido do Auth, mas houve falha ao limpar perfis:', deleteProfileError)
        return json({ erro: 'O acesso foi removido, mas houve falha ao limpar o cadastro. Solicite uma conferência ao gestor.' }, 500)
      }
      return json({ ok: true })
    }

    const email = String(body.email || '').trim()
    const senha = String(body.senha || '')
    const nome = String(body.nome || '').trim()
    const perfil = body.perfil
    if (!email || email.length > 254 || !email.includes('@') ||
        !nome || nome.length > 120 ||
        !['operador', 'tecnico', 'gestor'].includes(perfil) ||
        senha.length < 8 || senha.length > 128) {
      return json({ erro: 'Informe e-mail válido, nome, perfil e senha entre 8 e 128 caracteres.' }, 400)
    }

    const { data, error } = await admin.auth.admin.createUser({
      email, password: senha, email_confirm: true, user_metadata: { nome },
    })
    if (error) return json({ erro: error.message }, 400)

    const { error: upsertError } = await admin.from('perfis').upsert({
      id: data.user.id, nome, email, perfil,
    })
    if (upsertError) {
      const { error: rollbackError } = await admin.auth.admin.deleteUser(data.user.id)
      console.error('Falha ao criar perfil do usuário:', upsertError)
      if (rollbackError) {
        console.error('Falha ao desfazer usuário criado no Auth:', rollbackError)
        return json({ erro: 'O usuário foi criado no Auth, mas o cadastro do perfil falhou e a reversão também. É necessária uma conferência administrativa.' }, 500)
      }
      return json({ erro: 'Não foi possível salvar o perfil. A criação do usuário foi desfeita.' }, 500)
    }

    return json({ ok: true })
  } catch (error) {
    console.error('Erro em criar-usuario:', error)
    return json({ erro: 'Falha ao gerenciar usuário. Consulte os logs da função.' }, 500)
  }
})
