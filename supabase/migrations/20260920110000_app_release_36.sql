insert into public.app_releases (build, version, released_at, summary, items) values
  (36, '1.0', '2026-09-20',
   'Više screenshotova po stavci, pouzdaniji chat, prevedene greške.',
   array[
     'Ideje, bugovi i zadaci sad mogu imati više screenshotova (do 5), ne samo jedan.',
     'Popravljeno: chat poruke se ponekad nisu pojavljivale uživo nakon što bi app neko vrijeme bio u pozadini ili bi mreža nakratko pala — sad se automatski oporavlja umjesto da treba izaći i vratiti se u chat.',
     'Poruke grešaka koje dolaze iz servera sad su prevedene na odabrani jezik umjesto da se ponekad prikažu na hrvatskom bez obzira na postavku.'
   ])
on conflict (build) do nothing;
