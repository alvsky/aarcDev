-- B21 (prihvaćeno svjesno, prije G2): pregled pozivnice bez prijave.
--
-- invitations_select (B12) dopušta čitanje samo adminu organizacije — ispravno
-- za popis pozivnica, ali znači da POZVANA osoba ne može pročitati NIŠTA o
-- vlastitoj pozivnici prije nego se uopće prijavi (mora znati u koju
-- organizaciju i kojom ulogom, da zna treba li se prijaviti ili registrirati).
--
-- Token je 128-bitni UUID — praktički capability/tajna sama po sebi (isti
-- princip kao kod accept_invitation), pa vraćanje pregleda za KONKRETAN token
-- ne otvara adresar niti bilo što izvan onoga što pozivnica već sadrži.
--
-- ⚠️ Poznat i prihvaćen rizik dok G2 (potvrda e-maila) ne stigne: netko se
-- može registrirati s tuđom (nepotvrđenom) adresom i preuzeti pozivnicu prije
-- prave osobe. accept_invitation već uspoređuje e-mail sesije s pozivnicom;
-- ta provjera vrijedi onoliko koliko vrijedi da je adresa stvarno vlasnikova.
-- Zapisano u BACKLOG-u kao uvjet za zatvoriti prije javnog izlaska.

create or replace function public.get_invitation_preview(p_token uuid)
returns table (org_name text, role text, email text, expires_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select o.name, i.role, i.email, i.expires_at
    from invitations i
    join organizations o on o.id = i.org_id
   where i.token = p_token
     and i.accepted_at is null
     and i.expires_at > now()
$$;

-- Namjerno i za anon: pozvana osoba u pravilu još nema sesiju kad prvi put
-- otvori link. Anon vidi SAMO ono za konkretan token koji ionako posjeduje.
revoke all on function public.get_invitation_preview(uuid) from public;
grant execute on function public.get_invitation_preview(uuid) to anon, authenticated;
