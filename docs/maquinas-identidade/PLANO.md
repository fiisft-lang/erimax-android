# Identidade única de máquinas — preparação

## Estado
Esta branch é de preparação e não altera produção. Nenhuma migration foi executada no Supabase.

## Diagnóstico confirmado no schema
- `public.maquinas` possui `id bigint` como chave primária, além de `setor`, `nome` e `prefixo`.
- Há índice único global para `prefixo` normalizado (maiúsculas, sem espaços/símbolos), portanto a regra atual impede prefixos repetidos mesmo entre setores.
- `public.os` ainda não possui coluna `maquina_id`.
- `public.os.maquinas_execucao` é um array JSONB; os itens observados guardam `nome`, `concluida` e `concluida_em`, sem ID/código.
- `public.preventivas` também possui `maquina` (texto) e `maquinas` (JSONB), portanto o vínculo de preventivas precisa entrar no escopo.
- O cadastro possui 93 máquinas.

## Decisões de implementação
1. Usar `maquinas.id` como identidade técnica imutável; não usar nome como chave.
2. Manter nome, setor e prefixo como rótulos/dados de exibição.
3. Para O.S. de uma máquina, persistir `maquina_id` com FK para `maquinas.id`.
4. Para O.S. com várias máquinas, ampliar cada item de `maquinas_execucao` com `maquina_id` e snapshot do nome/código, mantendo os campos atuais para compatibilidade.
5. Atualizar a mesma estratégia nas preventivas e na criação das O.S. geradas por elas.
6. Exibir opções como `NOME — CÓDIGO — SETOR`, mas persistir o ID.
7. Não fazer backfill por nome quando houver mais de uma correspondência possível. Preservar registros legados ambíguos para revisão manual.
8. A O.S. 290 (MESA / SELADORA) permanece sem associação automática: existem duas máquinas de mesmo nome no setor, SL-11 e SL-12.
9. Manter o índice de prefixo global existente; não enfraquecer a regra de unicidade sem evidência de que a regra de negócio mudou.

## Escopo de validação antes de preview
- Cadastro/edição de máquinas: bloquear prefixo duplicado considerando normalização existente.
- Criação/edição de O.S. individual e múltipla: gravar e reabrir os IDs corretos.
- Preventivas: selecionar e persistir IDs para uma ou várias máquinas.
- Histórico e filtros: diferenciar equipamentos de mesmo nome usando ID, sem perder rótulos legíveis.
- Métricas: agregar por ID, e tratar registros legados sem ID sem atribuições inventadas.
- Testar O.S. 290 e outras O.S. legadas ambíguas sem alterar seus vínculos.

## Próximos passos
A implementação de frontend e a migration SQL só serão adicionadas depois de revisar todos os pontos de leitura/gravação do app. A migration será apenas arquivo versionado nesta branch; não será aplicada ao banco real.