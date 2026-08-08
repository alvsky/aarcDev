-- Item model, dio 3: poruke i vodenokazi dobivaju jedan item_id.
-- Model: docs/item-model.md
--
-- I dalje čisto aditivno: idea_id/bug_id/tbi_id ostaju i dalje se pune, pa
-- aplikacija na main radi nepromijenjeno. Stari stupci se brišu tek u M6.
--
-- Ovdje se dogodi spajanje threadova: kod spojenog para dva stara id-a pokazuju
-- na isti item_id u mapi, pa poruke iz OBA threada dobiju isti item_id i postaju
-- jedan razgovor. To je ono zbog čega badge koji se nije dao očistiti prestaje
-- biti moguć.

-- ---------------------------------------------------------------------------
-- Zaštita: dio 2 je mapirao samo ono što je tada postojalo. Ako je u
-- međuvremenu netko koristio staru aplikaciju i stvorio novu ideju/bug/TBI, ti
-- redci nemaju stavku i poruke bi im ostale bez odredišta. Radije glasan prekid
-- prije ijedne izmjene nego tiho nepotpuni podaci.
-- ---------------------------------------------------------------------------
do $$
declare n_ideas int; n_bugs int; n_tbi int;
begin
  select count(*) into n_ideas from public.ideas i
   where not exists (select 1 from public._item_migration_map m
                      where m.old_table = 'idea' and m.old_id = i.id);
  select count(*) into n_bugs from public.bugs b
   where not exists (select 1 from public._item_migration_map m
                      where m.old_table = 'bug' and m.old_id = b.id);
  select count(*) into n_tbi from public.tbi_items t
   where not exists (select 1 from public._item_migration_map m
                      where m.old_table = 'tbi' and m.old_id = t.id);

  if n_ideas + n_bugs + n_tbi > 0 then
    raise exception
      'Nije u mapi: % ideja, % bugova, % TBI. Nastali su starom aplikacijom nakon dijela 2 — treba catch-up prije nastavka.',
      n_ideas, n_bugs, n_tbi;
  end if;
end $$;

-- Invarijanta 4 (CLAUDE.md) nikad nije bila nametnuta ograničenjem. Ako je neka
-- poruka vezana na dvije stavke odjednom, donji UPDATE bi joj dodijelio
-- proizvoljnu — bolje stati i pogledati.
do $$
declare n int;
begin
  select count(*) into n from public.messages
   where (case when idea_id is not null then 1 else 0 end)
       + (case when bug_id  is not null then 1 else 0 end)
       + (case when tbi_id  is not null then 1 else 0 end) > 1;
  if n > 0 then
    raise exception '% poruka ima postavljeno više od jedne veze (idea/bug/tbi)', n;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- messages.item_id
-- ---------------------------------------------------------------------------
alter table public.messages
  add column item_id uuid references public.items(id) on delete cascade;

create index messages_item_id_idx on public.messages (item_id) where item_id is not null;

update public.messages m
   set item_id = map.item_id
  from public._item_migration_map map
 where (map.old_table = 'idea' and map.old_id = m.idea_id)
    or (map.old_table = 'bug'  and map.old_id = m.bug_id)
    or (map.old_table = 'tbi'  and map.old_id = m.tbi_id);

-- ---------------------------------------------------------------------------
-- message_reads.item_id
--
-- Namjerno BEZ novog unique indeksa: kod spojenog para korisnik može imati dva
-- vodenokaza (jedan za ideju, jedan za TBI) koji sada pokazuju na istu stavku.
-- Sažimanje duplikata i unique indeks idu u M6, kad stari stupci nestanu —
-- do tada bi novi indeks razbio postojeći upsert_message_read RPC.
-- ---------------------------------------------------------------------------
alter table public.message_reads
  add column item_id uuid references public.items(id) on delete cascade;

create index message_reads_item_id_idx
  on public.message_reads (user_id, item_id) where item_id is not null;

update public.message_reads r
   set item_id = map.item_id
  from public._item_migration_map map
 where (map.old_table = 'idea' and map.old_id = r.idea_id)
    or (map.old_table = 'bug'  and map.old_id = r.bug_id)
    or (map.old_table = 'tbi'  and map.old_id = r.tbi_id);

-- ---------------------------------------------------------------------------
-- Provjere
-- ---------------------------------------------------------------------------
do $$
declare n_bad int; n_merged int;
begin
  -- Svaka poruka u threadu stavke mora imati item_id.
  select count(*) into n_bad from public.messages
   where item_id is null
     and (idea_id is not null or bug_id is not null or tbi_id is not null);
  if n_bad > 0 then
    raise exception '% poruka je ostalo bez item_id', n_bad;
  end if;

  -- Poruke kanala (main/offtopic) NE smiju dobiti item_id.
  select count(*) into n_bad from public.messages
   where item_id is not null
     and idea_id is null and bug_id is null and tbi_id is null;
  if n_bad > 0 then
    raise exception '% poruka kanala je dobilo item_id', n_bad;
  end if;

  select count(*) into n_bad from public.message_reads
   where item_id is null
     and (idea_id is not null or bug_id is not null or tbi_id is not null);
  if n_bad > 0 then
    raise exception '% vodenokaza je ostalo bez item_id', n_bad;
  end if;

  -- Informativno: koliko je threadova stvarno spojeno.
  select count(*) into n_merged from (
    select item_id from public._item_migration_map
     group by item_id having count(*) > 1
  ) x;
  raise notice 'Spojenih parova (dvije stare stavke -> jedna): %', n_merged;
end $$;
