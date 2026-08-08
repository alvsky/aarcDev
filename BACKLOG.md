aarcDev — Backlog razrađen u samostalne točke
Organizirano po temama, ne po mjesecima — svaka točka je samostalan zadatak koji možeš uzeti kad želiš. Oznake: 🔴 kritično, 🟠 važno, 🟢 kad stigneš. Gdje postoji ovisnost, piše "⚠️ nakon".

A. Git i higijena projekta
✅ A1. Napraviti pravi inicijalni commit postojećeg stanja (riješeno 2026-08-08, commit c1d4857).
✅ A2. Postaviti remote repozitorij (GitHub) i push (riješeno 2026-08-08, https://github.com/alvsky/aarcDev).
🟠 A3. Dogovoriti granu-po-featureu workflow (main uvijek buildabilan).
✅ A4. Obrisati mrtve datoteke (riješeno 2026-08-08, commit df0f18c): BugCard-copy.vue, app-copy.scss, router/index-copy.js, example-store.js, src/i18n/en-US/. IndexPage.vue i SecondPage.vue su već obrisani.
🟢 A5. Ukloniti debug console.log iz storova i stranica (chat edit, project delete, demote, push flow, kompresija slika).

B. Sigurnost — migracija na višenajamnost (RLS)
Model i obrazloženje: docs/multi-tenancy.md. **Redoslijed nije proizvoljan** — backfill mora
proći prije nego politike postanu stroge, inače si zaključaš vlastite podatke. Sve ide kao
inkrementalne migracije (vidi C3), ne kao ručne izmjene u dashboardu.

Priprema
🔴 B1. Snimka baze prije početka. RLS promjene tiho lome realtime (realtime poštuje RLS) i nema
ih se lako vratiti unatrag. ⚠️ vidi F2 — idealno na staging okolini prvo.
🔴 B2. Auth postavke iz dashboarda u config.toml (sad ima 11 redaka, samo sekciju za edge
funkciju) — inače okolina nije reproducibilna.

Shema
🔴 B3. Tablice organizations, org_members, invitations. RLS uključen, bez ijedne politike
(zadano-zabranjeno).
🔴 B4. projects: dodati org_id (zasad nullable) i visibility text default 'org'.
🔴 B5. Backfill: jedna organizacija za postojeće podatke, svi postojeći korisnici kao članovi,
ti kao owner. ⚠️ nakon B3, B4.
🔴 B6. org_id → NOT NULL. ⚠️ nakon B5.

Funkcije za prava
🔴 B7. can_access_project(pid), is_org_member(oid), is_org_admin(oid), is_org_owner(oid) —
sve s `stable` i `set search_path = public`. Indeksi: org_members(user_id, org_id),
projects(org_id), project_members(user_id, project_id).
🔴 B8. Popraviti i postojeće is_member/is_owner istim modifikatorima (sad su VOLATILE bez
search_path — i performansni i sigurnosni problem).

Politike
🔴 B9. Sadržaj (ideas, bugs, tbi_items, messages, message_reactions) → svaka politika postaje
can_access_project(project_id). Zamjenjuje sve USING (true).
🔴 B10. projects INSERT → is_org_member(org_id). Sad je WITH CHECK (true), pa bi bilo tko mogao
ubaciti projekt u tuđu organizaciju. Lako se previdi.
🔴 B11. profiles SELECT → vlastiti redak ili suradnik iz iste organizacije. Sad je USING (true)
= otvoren adresar e-mailova cijelog sustava.
🔴 B12. org_members i project_members: pisanje zabranjeno svima. Sve kroz SECURITY DEFINER
RPC-e: accept_invitation, set_member_role, remove_member — svaki provjerava ulogu
pozivatelja. Zatvara sadašnju rupu (WITH CHECK (true) → svatko si doda članstvo i
postavi role='owner').
🔴 B13. Okidač: organizacija uvijek mora imati barem jednog ownera. Zadnji owner se ne može
razvlastiti ni izaći. Server-side, ne klijentski (pouka iz B18).
🔴 B14. upsert_message_read i get_unread_total: maknuti parametar p_user_id, koristiti
auth.uid() iznutra. Sad su SECURITY DEFINER s korisnikovim ID-em iz poziva bez provjere.

Posljedice modela
🔴 B15. get_unread_total i edge funkcija (push-on-message, popis primatelja) rade INNER JOIN na
project_members → s izračunatim pristupom članovi bez retka dobivaju nulu nepročitanih i
nikakav push. Prepisati na LEFT JOIN s podrazumijevanim vrijednostima. ⚠️ veliko
preklapanje s D1 — razmisliti o zajedničkoj izvedbi.
🟠 B16. Storage: politike u migraciju (sad postoje samo u dashboardu, neverzionirane), putanja
→ ${projectId}/${userId}/${uuid}.jpg, avatari u zasebnu kantu. Sadašnja putanja ne sadrži
projekt pa je projektno ograničenje nemoguće napisati. ⚠️ postojeći objekti imaju stare
putanje — treba odluka: migrirati ih ili podnijeti prekid na dev podacima.

Provjera
🔴 B17. Testovi izolacije: korisnik A ne vidi ništa iz organizacije korisnika B. Najvrjedniji
test u projektu. ⚠️ vidi E1 (Vitest).
🔴 B18. Regresija nakon zatezanja: manual profile joins, realtime događaji, thread_message_counts
view, edge funkcija (service role zaobilazi RLS — OK), offline keš.
🟠 B19. Server-side provjera zadnjeg vlasnika u delete_own_account() (sad samo klijentski).

Sučelje (nakon što baza stoji)
🟠 B20. Prebacivanje organizacije, upravljanje članovima i ulogama, prekidač vidljivosti
projekta pri kreiranju/uređivanju.
🟠 B21. Potvrda e-maila (G2) + pozivnice — **moraju ići zajedno**: bez potvrde e-maila se
registriraš s tuđom adresom i preuzmeš tuđu pozivnicu.

C. Baza — konzistentnost
🟠 C1. CHECK constrainti za statusne kolone: bug status, tbi status, priority, role, source_type, item_type, channel, platform.
🟠 C2. Atomarni create_project(name, desc, color) SQL RPC (projekt + owner u jednoj transakciji); prilagoditi projectsStore.createProject. Uklanja race i "projekt bez ownera" scenarij.
🟠 C3. Prijeći na inkrementalne migracije (svaka promjena = nova migracija; schema.sql ostaje kao dump referenca).
🟢 C4. Drop legacy tablica bug_reads i idea_reads.
🟢 C5. Čišćenje siročadi u item_reads (nema FK) — ili dodati trigger brisanja, ili periodički cleanup.
✅ C6. Brisanje screenshotova iz Storagea pri brisanju ideje/buga/TBI itema (riješeno 2026-08-05 — briše se i iz Storagea i iz lokalnog keša).

D. Performanse i skalabilnost
🟠 D1. Server-side unread: RPC/view koji vraća gotove brojeve po projektu/threadu umjesto da klijent dohvaća sve poruke. Ovo je najveći pojedinačni dobitak u aplikaciji.
🟠 D2. Debounce/throttle fetchUnread() poziva (sad se zove nakon skoro svakog realtime eventa). Samostalno izvedivo i prije D1.
🟠 D3. Filtrirati realtime kanale za message UPDATE i message_reactions po project_id (sad slušaju sve projekte).
🟢 D4. Paginacija poruka u threadovima (sad se učitava cijeli thread; limit + "učitaj starije").
🟢 D5. Batch dohvat signed URL-ova za slike (sad jedan poziv po slici).

E. Testovi i kvaliteta
🟠 E1. Uvesti Vitest; prvi testovi za čistu logiku: threadKey(), unread agregacija, is_new pravila, promote/demote tranzicije.
🟠 E2. GitHub Actions: lint:check + testovi na svaki push. ⚠️ nakon A2, E1.
🟠 E3. Ujednačen error handling: centralni wrapper oko store akcija + Quasar Notify za korisnika (sad greške uglavnom nestaju u konzoli). Konkretan primjer: `supabase.storage.from('chat-attachments').remove()` se poziva na više mjesta (brisanje buga/ideje/screenshota, uklanjanje avatara) i nigdje se ne provjerava vraćeni `error` — neuspjeh (npr. RLS odbije brisanje) prođe tiho, DB zapis se ažurira kao da je uspjelo, a objekt ostane sirotica u Storageu.
🟢 E4. Error reporting u produkciji (Sentry ili sličan).
🟢 E5. Playwright dim-test: login → kreiraj projekt → pošalji poruku → promote ideju.

F. Okoline i deploy
🟠 F1. Ukloniti hardkodirani project ref iz webhook triggera (parametrizirati po okolini).
🟠 F2. Staging Supabase projekt (schema + bucket + edge function + secrets).
🟢 F3. Dokumentirati postupak "podigni novu okolinu od nule" u docs/development.md. ⚠️ nakon F2.

G. Autentikacija i računi
🟠 G1. Reset lozinke (Supabase reset flow + stranica).
🟠 G2. Email verifikacija pri registraciji.
🟢 G3. Transfer ownershipa projekta (UI + pravila; preduvjet za elegantno brisanje računa).
✅ G4. Upload avatara (riješeno 2026-08-07) — UserAvatar komponenta (foto ili inicijali, skalira s postavkom veličine teksta preko --aarc-font-scale), upload/promjena/uklanjanje na Profilu, avatar_url dodan u sve profile select()-e i zamijenjeno svih 6 mjesta prikaza (MessageList, MemberDialog, ProjectsPage ×3, ProfilePage).

H. Suradnja i onboarding
🟠 H1. Invite flow: pozivnica emailom/linkom, pending stanje, prihvat nakon registracije (sad član mora već imati račun).
🟢 H2. Notifikacija "dodan si u projekt".
🟢 H3. Per-user postavke notifikacija finije od badge_enabled (npr. samo mentioni, samo threadovi u kojima sudjelujem).

I. Navigacija i UX
🟠 I1. Router refaktor: tabovi u URL-u (/project/:id/chat itd. — rute-djeca već postoje, samo ih iskoristiti), thread u URL-u za deep-link.
🟠 I2. Push notifikacija otvara konkretan projekt/thread (payload projectId/channel već putuje; pushNotificationActionPerformed listener postoji, samo loga). ⚠️ nakon I1.
🟢 I3. Offline UX: indikator mreže, disable slanja bez mreže, queue za neposlane poruke.
🟢 I4. Loading/skeleton stanja umjesto praznih lista tijekom fetcha.
🟢 I5. Potvrdni dijalozi ujednačiti (brisanje poruke/itema/projekta).
🟢 I6. UserAvatar (src/components/shared/UserAvatar.vue) — inicijali unutar kruga vizualno nisu točno centrirani (blago pomaknuti udesno), primijećeno i na jednoslovnim i dvoslovnim inicijalima. Isprobano: `<span>` umjesto raw teksta u `<template v-else>` (uklonilo susjedne prazne text-node-ove) — pomak i dalje vidljiv pa uzrok nije bio (samo) to. Vrijedi kad se vrati na ovo: provjeriti je li riječ o CSS boxu (q-avatar__content flex-center) ili o optičkom centriranju fonta (glyph ink vs advance-width box), pa po potrebi ručno kompenzirati (npr. mali transform/padding nudge).

J. TBI modul — proširenja
🟢 J1. Due date + sortiranje po prioritetu/roku.
🟢 J2. Filteri: po assigneeu, statusu, izvoru (getteri byStatus/bySource već postoje).
🟢 J3. Kanban pogled po statusu (razmisliti o proširenju statusa: tbi → in-progress → done).
🟢 J4. Notifikacija assigneeu kad mu se dodijeli item.

K. Chat — proširenja
🟢 K1. Push i za nove ideje/bugove/TBI iteme (sad samo poruke okidaju edge function).
🟢 K2. Mention (@ime) + push na mention.
🟢 K3. Pretraga poruka i itema (Postgres FTS je dovoljan).
🟢 K4. Ne-slikovni prilozi (PDF i sl.) — kolone attachment_type/name to već predviđaju.

L. Native / mobilno
🟠 L1. iOS FCM most: zamijeniti localStorage-polling pravim Capacitor bridge eventom ili notifikacijom iz nativnog koda; dodati retry. (Krhko: 30 s timeout.)
🟢 L2. TestFlight + Play internal track pipeline.
🟢 L3. Finalizacija ikona/splash za obje platforme.
🟢 L4. Provjeriti ponašanje badge-a kad je badge_enabled isključen za sve projekte.
M. Model stavke — spajanje u jednu tablicu
Model i obrazloženje: docs/item-model.md. Razlog: ideja i njezin TBI danas su dva retka s dva
threada, iz čega izravno slijedi sedam zasebnih grešaka (uključujući badge koji se ne da
očistiti). Radi se na grani, ne na main (vidi A3).

✅ M1. Model: kind × stage, kartice kao pogledi, pravilo "jedna stavka — jedan badge",
stupci autorstva, osobna oznaka "Pratim" (riješeno 2026-08-08, docs/item-model.md).
✅ M2. Tablice items + item_user_state + privremena mapa, i prijenos podataka
(migracije 20260808120000 i 20260808120100). Čisto aditivno — stare tablice netaknute.
🔴 M3. messages.item_id umjesto tri nullable FK-a; prevezivanje poruka preko mape (spaja
threadove spojenih parova). Usput otpada COALESCE unique indeks i prisila na
upsert_message_read RPC (invarijanta 3 u CLAUDE.md).
🔴 M4. Storovi: ideas/bugs/tbi → jedan items store. fetchUnread se bitno pojednostavljuje.
🔴 M5. Sučelje: kartice filtriraju po kind/stage, radnje Prihvati/Odbij umjesto promoviraj,
oznaka "Pratim" (oko) + filtar po njoj, sortiranje po priority.
🔴 M6. Brisanje starih tablica (ideas, bugs, tbi_items, item_reads), viewa
thread_message_counts i privremene mape. ⚠️ tek kad M3–M5 rade.
🟠 M7. Uskladiti dokumentaciju nakon M6: CLAUDE.md invarijante 3, 4 i 8, docs/database.md,
docs/workflows.md (tvrdi da lista ideja prikazuje i promovirane — kod to ne radi).

Preporučeni redoslijed ako želiš vodilju
Odmah, prije bilo čega: A1–A2 (git), zatim B1–B3 (RLS).
Sljedeći sloj: C2 (atomarni createProject), D1–D3 (unread + kanali), E1–E3.
Zatim po volji — sve ostale točke su međusobno uglavnom neovisne; ovisnosti su označene na točkama.
Reci ako želiš da neku točku razradim u detaljnu specifikaciju (npr. B1 — popis konkretnih politika po tablici, ili D1 — dizajn unread RPC-a).
