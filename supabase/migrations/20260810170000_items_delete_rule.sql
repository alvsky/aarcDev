-- Zatezanje brisanja stavki — zadnji labavi kraj u sadržajnim politikama.
--
-- Bilo je: using (auth.uid() = created_by or can_access_project(project_id))
-- Drugi uvjet je činio prvi suvišnim, pa je BILO KOJI član organizacije mogao
-- obrisati bilo čiju ideju ili bug — a s time kaskadno i cijeli razgovor.
--
-- Nesklad je bio očit: tuđu poruku se nije moglo ni urediti, ali cijelu stavku s
-- pedeset poruka jest obrisati. Kod postavljanja tog pravila (M2) stajala je
-- bilješka "pooštriti kad stignu uloge organizacije" — sada su tu.
--
-- Novo pravilo prati ono koje već vrijedi za projekte (B10): autor briše svoje,
-- admin organizacije bilo što. Time se može počistiti za nekim tko je otišao, a
-- obična pogreška ne odnosi tuđi rad.
--
-- Uređivanje ostaje otvoreno namjerno: mijenjanje faze, prioriteta i izvršitelja
-- je sama bit zajedničkog rada. Brisanje je jedina radnja koja se ne vraća.

create or replace function public.is_project_org_admin(pid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from projects p
    join org_members om on om.org_id = p.org_id and om.user_id = auth.uid()
     where p.id = pid and om.role in ('owner', 'admin')
  )
$$;

drop policy if exists items_delete on public.items;

create policy items_delete on public.items
  for delete to authenticated
  using (
    -- Pristup je preduvjet i autoru: tko je izgubio članstvo u organizaciji ne
    -- briše ni ono što je sam napisao. Kvar ide u sigurnu stranu.
    public.can_access_project(project_id)
    and (auth.uid() = created_by or public.is_project_org_admin(project_id))
  );

-- Napomena: brisanje PORUKA ostaje isključivo autorovo. Admin može obrisati
-- cijelu stavku (i time njezin thread), ali ne pojedinu tuđu poruku —
-- moderiranje chata je zasebna značajka i nije dio ovoga.
