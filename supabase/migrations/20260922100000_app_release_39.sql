insert into public.app_releases (build, version, released_at, summary, items) values
  (39, '1.0', '2026-09-22',
   'Više slika u chatu i popravljen kontrast u tamnoj temi.',
   array[
     'U chatu sad možeš zalijepiti, povući ili odabrati više slika odjednom — svaka ide kao zasebna poruka.',
     'Popravljen kontrast u tamnoj temi: oznake stanja/prioriteta na idejama/bugovima/zadacima su ponovno u boji, zatvorene stavke su čitljivije, a uključeni filteri (npr. "Prikaži zatvorene") su sad jasno vidljivi.',
     'Sitni popravci izgleda: gumb za dodavanje nove stavke uvijek ostaje na istom mjestu, natpis "Svijetla tema" više se ne prikazuje na engleskom kad je odabran hrvatski jezik.'
   ])
on conflict (build) do nothing;
