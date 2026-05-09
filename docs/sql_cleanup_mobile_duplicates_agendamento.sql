-- Limpeza de duplicados indevidos do fluxo móvel em agendamento_servico
-- Objetivo: remover espelhos MOVEL criados por dual-write antigo.
-- Segurança: executar primeiro os blocos de auditoria (SELECT), validar amostra e só então executar DELETE.

-- 1) Auditoria prévia: contagem total de MOVEL sem data_agendada
select
  count(*) as total_movel_sem_data
from public.agendamento_servico a
where upper(coalesce(a.tipo_fluxo, '')) = 'MOVEL'
  and a.data_agendada is null;

-- 2) Auditoria prévia: amostra dos registros candidatos
select
  a.id,
  a.cliente_uid,
  a.prestador_uid,
  a.status,
  a.preco_total,
  a.valor_entrada,
  a.created_at
from public.agendamento_servico a
where upper(coalesce(a.tipo_fluxo, '')) = 'MOVEL'
  and a.data_agendada is null
order by a.created_at desc
limit 50;

-- 3) DELETE (habilitar somente após validar a auditoria acima)
-- begin;
-- delete from public.agendamento_servico a
-- where upper(coalesce(a.tipo_fluxo, '')) = 'MOVEL'
--   and a.data_agendada is null;
-- commit;

-- 4) Auditoria pós-limpeza
-- select count(*) as total_movel_sem_data_pos
-- from public.agendamento_servico a
-- where upper(coalesce(a.tipo_fluxo, '')) = 'MOVEL'
--   and a.data_agendada is null;
