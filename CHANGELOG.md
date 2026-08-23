# Changelog

Zapis promjena vidljivih korisniku. Tehnički detalji i obrazloženja odluka su u
`BACKLOG.md` (po točkama) i u porukama commitova.

Format verzije prati iOS: **marketinška verzija** (1.0) + **build** (raste sa
svakim isporučenim buildom). Android `versionCode`/`versionName` i
`package.json` drže se istih brojeva.

---

## v1.0 (build 28) — 2026-08-23

Poruke koje nestaju nakon čitanja, i chat prilagođen desktopu.

- Nova opcija u chatu: poruka koja nestaje nakon čitanja. Uključi se gumbom s
  ikonom vatre pored polja za unos poruke; ostalim članovima se prikaže kao
  skriven mjehurić dok ga ne otvore, a sadržaj se u tom trenutku nepovratno
  briše (uključno s privitkom). Kad je pročitaju svi članovi projekta, u
  chatu ostaje samo trag "Otvoreno" — vidljiv svima, kao kod WhatsAppa.
- Chat thread (otvoren iz ideje/buga/zadatka) sad ima istu ograničenu širinu
  kao ostatak aplikacije na tabletu/desktopu — dosad se razvlačio preko
  cijelog ekrana.

---

## v1.0 (build 27) — 2026-08-15

Registracija konačno radi, pozivnice se šalju e-mailom.

- Popravljena registracija/prijava koja je vraćala grešku 500 — Resend SMTP
  pošiljatelj je koristio testnu (sandbox) adresu koja je smjela slati samo
  vlasniku Resend računa, pa nitko drugi nije mogao dovršiti registraciju.
  Sad koristi pravu, verificiranu domenu.
- Neuspjela prijava/registracija/reset lozinke sad prikazuje razumljivu
  poruku umjesto sirove (ponekad prazne, vidljive kao gole vitičaste zagrade)
  greške sa servera.
- Pozivnice u organizaciju sad stižu i e-mailom (uz link koji se i dalje
  kopira u međuspremnik) — prije se link morao ručno proslijediti.
- Nova web stranica za prihvat pozivnice (za nekoga tko još nema instaliranu
  app) — prijava/registracija i pridruživanje organizaciji izravno u
  pregledniku.
- Uklonjena "Ctrl+V za lijepljenje" uputa na mobilnim uređajima (nema
  smisla bez tipkovnice); na webu sad piše i za Mac (Cmd+V).

---

## v1.0 (build 26) — 2026-08-14

Android app ikona, dostupnija navigacija i nove stranice.

- Android app ikona zamijenjena pravim aarc logom (dosad je bio zadani
  Capacitorov placeholder).
- Podnožje s navigacijom (Home / Organizacija / Profil) sad je vidljivo i na
  stranicama Organizacije i Profila, ne samo na Homeu.
- Nove stranice "O aplikaciji" (verzija, build broj) i "Pravila privatnosti",
  dostupne iz Postavki.

---

## v1.0 (build 25) — 2026-08-13

Android push notifikacije i popravci dodira na notifikaciju.

- Android push notifikacije sad rade (dosad nikad nisu, nedostajala je
  konfiguracija).
- Dodir na notifikaciju za komentar unutar ideje/buga/zadatka sad otvara baš
  taj thread umjesto uvijek Rasprave.
- Dodir na notifikaciju dok je app u pozadini (ne ugašena) sad ispravno otvara
  cilj, umjesto da ostane na trenutnom zaslonu.
- Dodir na notifikaciju za drugi projekt sad stvarno prebaci na taj projekt,
  umjesto da samo promijeni karticu unutar starog.
- Notifikacija se sad pojavljuje i dok gledaš app (prije se pojavljivala samo
  kad je app u pozadini ili ugašena) — kratki banner s gumbom "Otvori", osim
  kad si već unutar tog istog projekta.
- U poruku se sad može upisati novi red (Enter na mobitelu više ne šalje
  poruku odmah).

---

## v1.0 (build 24) — 2026-08-12

Dotjerivanje razmaka nakon prvog testiranja na uređaju.

- Pod-tabovi u chatu (Rasprava / Offtopic) zauzimaju upola manje visine — taj
  prostor sad ide popisu poruka.
- Manje praznog prostora pri dnu početnog zaslona.
- Donja navigacija više nema upadljivu praznu traku ispod natpisa.
- Popis ideja/bugova/zadataka: alatna traka s filtrima ostaje na mjestu dok se
  popis skrola (prije se moralo skrolati skroz na vrh da bi se promijenio
  filtar), a suvišan naslov iznad nje je maknut — kartica u zaglavlju već kaže
  gdje si.
- Prijelomi redaka u opisima i koracima za reprodukciju se čuvaju pri prikazu.

---

## v1.0 (build 23) — 2026-08-12

Prva zabilježena verzija. Obuhvaća sve dosad napravljeno, ne samo zadnji krug.

### Organizacije i članovi

- Organizacija je gornja razina — projekti pripadaju organizaciji, korisnik
  može biti u više njih i prebacivati se između njih.
- Uloge: vlasnik, admin, član, gost. Prebacivanje uloga, prijenos vlasništva,
  uklanjanje članova i napuštanje organizacije.
- Organizacija uvijek mora imati barem jednog vlasnika — zadnji vlasnik se ne
  može razvlastiti ni obrisati račun dok ne prenese vlasništvo.
- Pozivnice: vlasnik/admin pošalje pozivnicu (e-mail + uloga) i dobije link za
  kopiranje. Pozvana osoba se prijavi ili registrira tom adresom i automatski
  ulazi u organizaciju.
- Vlasnik vidi statistiku po članu (broj projekata u kojima je aktivan,
  prijavljene ideje/bugovi/zadaci, dodijeljene stavke).

### Projekti

- Vidljivost projekta: cijeloj organizaciji ili privatno (samo dodani članovi).
- Prikvačeni projekti — osobna oznaka, uvijek na vrhu popisa.
- Pretraga projekata po nazivu i prebacivanje sortiranja (nepročitano ↔ naziv).
- Praćenje projekta je odvojeno od pristupa: obavijesti počinješ dobivati kad
  prvi put napišeš poruku ili ti se nešto dodijeli, a ne za svaki projekt koji
  smiješ vidjeti.

### Ideje, bugovi i zadaci

- Ideje, bugovi i TBI su sad **jedna te ista stavka** koja mijenja fazu, ne tri
  odvojena zapisa. Prihvaćanje ideje je premješta na TBI ploču zajedno s cijelom
  dosadašnjom prepiskom — ništa se ne gubi ni ne duplicira.
- Radnje Prihvati / Odbij / Vrati u razmatranje umjesto "promoviranja".
- Osobna oznaka "Pratim" (oko) i filtar po njoj.
- Bugovi: platforma na kojoj se dogodio (iOS/Android/Web, unaprijed popunjena) i
  koraci za reprodukciju.
- Pretraga po projektu — naslovi i opisi svih stavki, uključujući zatvorene;
  opcionalno i sadržaj poruka. Ne smeta joj dijakritika ("veličina" nalazi
  "Velicina").

### Chat i obavijesti

- Jedan chat po stavci, kroz cijeli njezin životni ciklus.
- Kanali `main` i `offtopic`, odgovori na poruku, reakcije, slike.
- Dodir na push notifikaciju otvara točan projekt, karticu i thread.
- Broj nepročitanog: jedna stavka nosi točno jedan badge, na kartici gdje traži
  pažnju — nema više brojeva koji se ne daju očistiti.
- Postavke obavijesti po projektu i po kategoriji.

### Račun

- Registracija s potvrdom e-maila.
- Reset zaboravljene lozinke preko e-maila.
- Promjena lozinke iz profila (uz potvrdu trenutne).
- Avatar (fotografija ili inicijali), promjena imena, brisanje računa.

### Ostalo

- Radi offline: spremljeni podaci ostaju dostupni, neposlane poruke čekaju u
  redu i šalju se kad se veza vrati.
- Tamna tema, veličina teksta, hrvatski/engleski.
- Sadržaj je ograničene širine na tabletu/desktopu umjesto da se razvuče preko
  cijelog ekrana.
