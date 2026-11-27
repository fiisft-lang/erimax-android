-- Cadastro de material com saldo inicial registrado como movimentação de entrada.
-- O formulário já possui descrição; adicionamos a coluna opcional ausente no schema.
-- A operação é atômica: se a entrada falhar, o cadastro inteiro é revertido.
alter table public.almox_materiais add column if not exists descricao text;

create or replace function public.almox_cadastrar_material(
  p_nome text,
  p_codigo text,
  p_categoria text,
  p_unidade text,
  p_estoque_minimo numeric,
  p_localizacao text,
  p_descricao text,
  p_quantidade_inicial numeric
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid;
  v_material_id uuid;
  v_quantidade numeric(14,3) := coalesce(p_quantidade_inicial, 0);
begin
  v_uid := auth.uid();

  if v_uid is null or coalesce(public.meu_perfil(), '') <> 'gestor' then
    raise exception 'Acesso exclusivo do Gestor.';
  end if;

  if nullif(btrim(p_nome), '') is null or length(btrim(p_nome)) > 160 then
    raise exception 'Informe um nome válido para o material.';
  end if;
  if v_quantidade < 0 then
    raise exception 'A quantidade inicial não pode ser negativa.';
  end if;
  if coalesce(p_estoque_minimo, 0) < 0 then
    raise exception 'O estoque mínimo não pode ser negativo.';
  end if;
  if nullif(btrim(p_unidade), '') is null then
    raise exception 'Selecione a unidade do material.';
  end if;

  insert into public.almox_materiais (
    nome, codigo, categoria, unidade, estoque_minimo,
    localizacao, descricao, quantidade_atual, criado_por
  ) values (
    btrim(p_nome), nullif(btrim(coalesce(p_codigo, '')), ''),
    nullif(btrim(coalesce(p_categoria, '')), ''), btrim(p_unidade),
    coalesce(p_estoque_minimo, 0),
    nullif(btrim(coalesce(p_localizacao, '')), ''),
    nullif(btrim(coalesce(p_descricao, '')), ''), 0, v_uid
  )
  returning id into v_material_id;

  if v_quantidade > 0 then
    insert into public.almox_movimentacoes (
      material_id, tipo, quantidade, motivo, criado_por
    ) values (
      v_material_id, 'entrada', v_quantidade,
      'Estoque inicial no cadastro do material', v_uid
    );
  end if;

  return v_material_id;
end;
$function$;

revoke all on function public.almox_cadastrar_material(text,text,text,text,numeric,text,text,numeric) from public, anon, authenticated;
grant execute on function public.almox_cadastrar_material(text,text,text,text,numeric,text,text,numeric) to authenticated;
