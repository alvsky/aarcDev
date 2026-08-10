-- § B6: org_id postaje obavezan.
--
-- Backfill (B5) je potvrđen — svaki projekt ima organizaciju. Od sada projekt
-- bez najma nije moguć, što je preduvjet da se can_access_project uopće smije
-- osloniti na join preko org_id.
--
-- Bez utjecaja na pristup: mijenja se samo integritet, nijedna politika.

do $$
declare n int;
begin
  select count(*) into n from public.projects where org_id is null;
  if n > 0 then
    raise exception '% projekata nema org_id — pokreni backfill (B5) prije ovoga', n;
  end if;
end $$;

alter table public.projects alter column org_id set not null;
