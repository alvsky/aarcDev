insert into public.app_releases (build, version, released_at, summary, items) values
  (34, '1.0', '2026-09-03',
   'Privremeno uklonjena opcija poruke koja nestaje nakon čitanja.',
   array[
     'Privremeno uklonjena opcija poruke koja nestaje nakon čitanja (gumb s ikonom vatre pored polja za unos poruke) — vraća se kasnije.'
   ])
on conflict (build) do nothing;
