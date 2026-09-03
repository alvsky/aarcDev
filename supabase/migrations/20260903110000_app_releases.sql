-- Verzija i changelog prikazani u appu (Postavke → O aplikaciji, Popis
-- promjena) su dosad bili hardkodirani na DVA mjesta u frontendu
-- (AboutPage.vue appVersion/appBuild, ChangelogPage.vue entries[]) — uz
-- CHANGELOG.md i tri build-datoteke (pbxproj/build.gradle/package.json) to
-- je bilo šest mjesta za ručno ažurirati na svaki release, i jedno se već
-- zaboravilo (2026-09-03, app je nakon nadogradnje na build 33 i dalje
-- prikazivala build 30). Ova tablica je jedini izvor za ta dva app-ova
-- ekrana; build-datoteke ostaju zasebne jer su to platformski metapodaci
-- ugrađeni u binarku prije nego app ikad kontaktira Supabase, a CHANGELOG.md
-- ostaje developerski zapis u repou.
create table if not exists public.app_releases (
  build       integer primary key,
  version     text not null,
  released_at date not null,
  summary     text not null,
  items       text[] not null default '{}'
);

alter table public.app_releases enable row level security;

-- Javni podatak o samoj aplikaciji, ne vezan za organizaciju/projekt — čita
-- ga svatko prijavljen, piše se samo ručno (migracija/dashboard), namjerno
-- bez insert/update/delete politike za authenticated.
create policy "app_releases_select" on public.app_releases
  for select to authenticated using (true);

insert into public.app_releases (build, version, released_at, summary, items) values
  (33, '1.0', '2026-09-03',
   'Linkovi u chatu, hrvatski datumi i popravak poruka koje se nisu pojavljivale.',
   array[
     'Link napisan u chatu sad je klikabilan i otvara se u pregledniku.',
     'Datumi i vrijeme su svugdje u hrvatskom formatu (npr. "03.09.2026." i "14:30"), uključujući razdjelnike dana u chatu ("Danas, 03.09.2026.").',
     'Popravljeno: poslana poruka se ponekad nije pojavila u chatu dok se ne bi izašlo i vratilo u projekt.',
     'Dva projekta s istim nazivom unutar iste organizacije više nisu moguća.',
     'Poruka koja nestaje nakon čitanja sad iz chata nestaje u potpunosti — više ne ostavlja trag "Otvoreno" uveden u buildu 28.'
   ]),
  (30, '1.0', '2026-08-23',
   'Popis promjena, sad i u samoj aplikaciji.',
   array[
     'Nova stranica "Popis promjena", dostupna iz Postavki → O aplikaciji — pregled svih dosadašnjih izdanja bez potrebe za GitHubom.'
   ]),
  (28, '1.0', '2026-08-23',
   'Poruke koje nestaju nakon čitanja, i chat prilagođen desktopu.',
   array[
     'Nova opcija u chatu: poruka koja nestaje nakon čitanja. Uključi se gumbom s ikonom vatre pored polja za unos poruke; ostalim članovima se prikaže kao skriven mjehurić dok ga ne otvore, a sadržaj se u tom trenutku nepovratno briše (uključno s privitkom). Kad je pročitaju svi članovi projekta, u chatu ostaje samo trag "Otvoreno" — vidljiv svima, kao kod WhatsAppa.',
     'Chat thread (otvoren iz ideje/buga/zadatka) sad ima istu ograničenu širinu kao ostatak aplikacije na tabletu/desktopu — dosad se razvlačio preko cijelog ekrana.'
   ]),
  (27, '1.0', '2026-08-15',
   'Registracija konačno radi, pozivnice se šalju e-mailom.',
   array[
     'Popravljena registracija/prijava koja je vraćala grešku 500 — Resend SMTP pošiljatelj je koristio testnu (sandbox) adresu koja je smjela slati samo vlasniku Resend računa, pa nitko drugi nije mogao dovršiti registraciju. Sad koristi pravu, verificiranu domenu.',
     'Neuspjela prijava/registracija/reset lozinke sad prikazuje razumljivu poruku umjesto sirove (ponekad prazne, vidljive kao gole vitičaste zagrade) greške sa servera.',
     'Pozivnice u organizaciju sad stižu i e-mailom (uz link koji se i dalje kopira u međuspremnik) — prije se link morao ručno proslijediti.',
     'Nova web stranica za prihvat pozivnice (za nekoga tko još nema instaliranu app) — prijava/registracija i pridruživanje organizaciji izravno u pregledniku.',
     'Uklonjena "Ctrl+V za lijepljenje" uputa na mobilnim uređajima (nema smisla bez tipkovnice); na webu sad piše i za Mac (Cmd+V).'
   ]),
  (26, '1.0', '2026-08-14',
   'Android app ikona, dostupnija navigacija i nove stranice.',
   array[
     'Android app ikona zamijenjena pravim aarc logom (dosad je bio zadani Capacitorov placeholder).',
     'Podnožje s navigacijom (Home / Organizacija / Profil) sad je vidljivo i na stranicama Organizacije i Profila, ne samo na Homeu.',
     'Nove stranice "O aplikaciji" (verzija, build broj) i "Pravila privatnosti", dostupne iz Postavki.'
   ]),
  (25, '1.0', '2026-08-13',
   'Android push notifikacije i popravci dodira na notifikaciju.',
   array[
     'Android push notifikacije sad rade (dosad nikad nisu, nedostajala je konfiguracija).',
     'Dodir na notifikaciju za komentar unutar ideje/buga/zadatka sad otvara baš taj thread umjesto uvijek Rasprave.',
     'Dodir na notifikaciju dok je app u pozadini (ne ugašena) sad ispravno otvara cilj, umjesto da ostane na trenutnom zaslonu.',
     'Dodir na notifikaciju za drugi projekt sad stvarno prebaci na taj projekt, umjesto da samo promijeni karticu unutar starog.',
     'Notifikacija se sad pojavljuje i dok gledaš app (prije se pojavljivala samo kad je app u pozadini ili ugašena) — kratki banner s gumbom "Otvori", osim kad si već unutar tog istog projekta.',
     'U poruku se sad može upisati novi red (Enter na mobitelu više ne šalje poruku odmah).'
   ]),
  (24, '1.0', '2026-08-12',
   'Dotjerivanje razmaka nakon prvog testiranja na uređaju.',
   array[
     'Pod-tabovi u chatu (Rasprava / Offtopic) zauzimaju upola manje visine — taj prostor sad ide popisu poruka.',
     'Manje praznog prostora pri dnu početnog zaslona.',
     'Donja navigacija više nema upadljivu praznu traku ispod natpisa.',
     'Popis ideja/bugova/zadataka: alatna traka s filtrima ostaje na mjestu dok se popis skrola (prije se moralo skrolati skroz na vrh da bi se promijenio filtar), a suvišan naslov iznad nje je maknut — kartica u zaglavlju već kaže gdje si.',
     'Prijelomi redaka u opisima i koracima za reprodukciju se čuvaju pri prikazu.'
   ]),
  (23, '1.0', '2026-08-12',
   'Prva zabilježena verzija. Obuhvaća sve dosad napravljeno, ne samo zadnji krug.',
   array[
     'Organizacije s ulogama (vlasnik, admin, član, gost), pozivnice, statistika po članu.',
     'Projekti: vidljivost, prikvačeni projekti, pretraga, praćenje odvojeno od pristupa.',
     'Ideje, bugovi i TBI kao jedna stavka koja mijenja fazu — prihvaćanje ništa ne duplicira.',
     'Jedan chat po stavci — kanali, odgovori, reakcije, slike, push notifikacije, brojevi nepročitanog.',
     'Registracija, reset lozinke, avatar, offline rad, tamna tema, hrvatski/engleski.'
   ])
on conflict (build) do nothing;
