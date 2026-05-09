# Supabase Worktree Guide

## Fonte Canônica

- **Canônica para deploy e produção:** `/home/servirce/Documentos/101/projeto-central-/supabase`
- **Atalho compatível no app mobile:** `/home/servirce/Documentos/101/projeto-central-/mobile_app/supabase` (symlink para `../supabase`)

O `project-ref` ativo está em:

- `/home/servirce/Documentos/101/projeto-central-/supabase/.temp/project-ref`

## Regra Operacional

1. Deploy oficial sempre a partir de `projeto-central-/supabase`.
2. `mobile_app/supabase` existe apenas como symlink de compatibilidade.
3. Antes de deploy, rodar:

```bash
cd /home/servirce/Documentos/101/projeto-central-/mobile_app
./scripts/supabase_guard.sh check
```

4. Política obrigatória de webhook/API pública:

```toml
[functions.api]
verify_jwt = false
```

O `supabase_guard.sh check` agora falha automaticamente se esse bloco for alterado.

## Deploy Seguro (recomendado)

```bash
cd /home/servirce/Documentos/101/projeto-central-/mobile_app
./scripts/supabase_guard.sh deploy api post_action get-available-services
```

## Por que isso evita erro

- Evita empacotar funções da árvore errada.
- Evita usar `_shared` incompatível entre worktrees diferentes.
- Garante que `project-ref` e `config.toml` do ambiente oficial sejam usados a partir da pasta única.
