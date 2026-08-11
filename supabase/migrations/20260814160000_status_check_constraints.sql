-- C1: preostale statusne kolone dobivaju CHECK, isti obrazac kao items
-- (kind/stage/priority, M2) i novi items.platform (N1) — cijena je
-- najniža baš sad, dok je vrijednosti malo i poznato.
--
-- Vrijednosti potvrđene pretragom koda, ne pogađanjem:
-- project_members.role — samo 'owner'/'member' (set_project_member_role RPC
--   već to provodi na aplikacijskoj razini, ovo je obrana u dubinu).
-- push_tokens.platform — 'ios'/'android' u praksi (usePush.js registrira samo
--   na native platformama); 'web' dopušten da ne zabranimo nešto bezazleno.
-- messages.channel — 'main'/'offtopic' ili null (null = thread stavke, ima
--   item_id umjesto kanala).
alter table public.project_members
  add constraint project_members_role_check
  check (role is null or role in ('owner', 'member'));

alter table public.push_tokens
  add constraint push_tokens_platform_check
  check (platform is null or platform in ('ios', 'android', 'web'));

alter table public.messages
  add constraint messages_channel_check
  check (channel is null or channel in ('main', 'offtopic'));
