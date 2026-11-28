-- التراجع عن الترحيل 54: يزيل السلسلة وحماية التعديل. يفقد السجل أدلة السلامة (البصمات) فقط، لا الأحداث.
drop trigger if exists audit_chain_truncate_trg on public.audit_log;
drop trigger if exists audit_chain_guard_trg on public.audit_log;
drop trigger if exists audit_chain_insert_trg on public.audit_log;
drop function if exists public.security_audit_verify();
drop function if exists public.audit_chain_guard();
drop function if exists public.audit_chain_insert();
drop function if exists public.audit_row_hash(public.audit_log, text);
drop index if exists public.audit_log_chain_no_idx;
alter table public.audit_log drop column if exists row_hash;
alter table public.audit_log drop column if exists prev_hash;
alter table public.audit_log drop column if exists chain_no;
