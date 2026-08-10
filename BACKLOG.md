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
🟠 B0. Ograničiti Firebase iOS API ključ (Google Cloud Console → Credentials →
Application restrictions → iOS apps → bundle ID com.vitka.collabapp; API restrictions →
samo FCM). GitHub secret scanning ga je prijavio 2026-08-09 u GoogleService-Info.plist —
NIJE tajna (klijentska konfiguracija, ionako se isporučuje u aplikaciji i vadi iz IPA), pa
rotacija nema smisla; ograničenje je jedina stvarna mjera. Alert zatvoriti kao "won't fix".
⚠️ Bitnije od toga: Supabase anon ključ je jednako javan i bezopasan SAMO ako RLS radi —
danas ne radi, što je razlog za ostatak ove sekcije.
✅ B1. (2026-08-10) Snimka baze prije početka. RLS promjene tiho lome realtime (realtime poštuje RLS) i nema
ih se lako vratiti unatrag. ⚠️ vidi F2 — idealno na staging okolini prvo.
🔴 B2. Auth postavke iz dashboarda u config.toml (sad ima 11 redaka, samo sekciju za edge
funkciju) — inače okolina nije reproducibilna.

Shema
✅ B3. (2026-08-09) Tablice organizations, org_members, invitations. RLS uključen, bez ijedne politike
(zadano-zabranjeno).
✅ B4. (2026-08-09) projects: dodati org_id (zasad nullable) i visibility text default 'org'. NOVI projekti
se kreiraju kao 'private' — prebacivanje na 'org' je admin radnja (vidi matricu u docs).
✅ B5. (2026-08-09) Backfill: jedna organizacija za postojeće podatke, svi postojeći korisnici kao članovi,
ti kao owner. ⚠️ nakon B3, B4.
✅ B6. (2026-08-10) org_id → NOT NULL. ⚠️ nakon B5.

Funkcije za prava
✅ B7. (2026-08-10) can_access_project(pid), is_org_member(oid), is_org_admin(oid), is_org_owner(oid) —
sve s `stable` i `set search_path = public`. Indeksi: org_members(user_id, org_id),
projects(org_id), project_members(user_id, project_id).
⚠️ Funkcija ima granu `om.role in ('owner','admin')` — admini vide SVE projekte svoje
organizacije, i privatne. Bez toga član može stvoriti projekt koji njegov vlasnik ne vidi.
✅ B8. (2026-08-10) Popraviti i postojeće is_member/is_owner istim modifikatorima (sad su VOLATILE bez
search_path — i performansni i sigurnosni problem).

Politike
✅ B9. (2026-08-10) Sadržaj (messages, message_reactions) → svaka politika postaje
can_access_project(project_id). Zamjenjuje sve USING (true). items to već ima od M2, pa je
ovo samo dovođenje ostatka na istu razinu.
✅ B10. (2026-08-10) projects INSERT → is_org_member(org_id) AND (visibility='private' OR
is_org_admin(org_id)). Sad je WITH CHECK (true), pa bi bilo tko mogao ubaciti projekt u tuđu
organizaciju. Lako se previdi.
✅ B10b. (2026-08-10) Okidač BEFORE UPDATE na projects: promjena visibility samo za admina/ownera. Mora
biti okidač, ne WITH CHECK — pravilo se tiče PRIJELAZA, a WITH CHECK vidi samo novi redak pa
bi članu blokirao i obično preimenovanje već podijeljenog projekta.
✅ B11. (2026-08-10) profiles SELECT → vlastiti redak ili suradnik iz iste organizacije. Sad je USING (true)
= otvoren adresar e-mailova cijelog sustava.
✅ B12. (2026-08-10) org_members i project_members: pisanje zabranjeno svima. Sve kroz SECURITY DEFINER
RPC-e: accept_invitation, set_member_role, remove_member — svaki provjerava ulogu
pozivatelja. Zatvara sadašnju rupu (WITH CHECK (true) → svatko si doda članstvo i
postavi role='owner').
✅ B13. (2026-08-10) Okidač: organizacija uvijek mora imati barem jednog ownera. Zadnji owner se ne može
razvlastiti ni izaći. Server-side, ne klijentski (pouka iz B18).
✅ B14. (2026-08-10) Potpis je ostao — edge funkcija legitimno računa za drugoga. Umjesto
toga je oduzeto pravo pozivanja roli authenticated; iste mjere dobile su i _unread_rows,
push_recipients i dvoargumentni can_access_project.

Posljedice modela
✅ B15. (2026-08-10, s D1) — notificationsStore.fetchUnread, get_unread_total i edge funkcija
(popis primatelja) sve voze iz project_members. Radi samo zato što postojeći projekti imaju
te retke od prije. Čim se napravi NOVI projekt vidljiv organizaciji, ostali članovi nemaju
redak → nula nepročitanih i nikakav push, bez ijedne greške. Prepisati na "članovi
organizacije koji imaju pristup", uz project_members samo kao izvor osobnih postavki
(LEFT JOIN + podrazumijevane vrijednosti). ⚠️ veliko preklapanje s D1.
🟠 B16. Storage: politike u migraciju (sad postoje samo u dashboardu, neverzionirane), putanja
→ ${projectId}/${userId}/${uuid}.jpg, avatari u zasebnu kantu. Sadašnja putanja ne sadrži
projekt pa je projektno ograničenje nemoguće napisati. ⚠️ postojeći objekti imaju stare
putanje — treba odluka: migrirati ih ili podnijeti prekid na dev podacima.

Provjera
🔴 B17. Testovi izolacije: korisnik A ne vidi ništa iz organizacije korisnika B. Najvrjedniji
test u projektu. ⚠️ vidi E1 (Vitest).
🔴 B18. Regresija nakon zatezanja: manual profile joins, realtime događaji, item_message_counts
view (security_invoker — mijenja se ponašanje kad politike postanu stroge!), edge funkcija
(service role zaobilazi RLS — OK), offline keš.
🟠 B19. delete_own_account(): provjera zadnjeg vlasnika JE od B13 na poslužitelju (okidač
odbija kaskadno brisanje zadnjeg vlasnika). Preostaje samo da aplikacija tu iznimku uhvati i
pokaže čitljivu poruku umjesto sirove Postgres greške.

Sučelje (nakon što baza stoji)
🟠 B20. Home i ekran organizacije — makro po specifikaciji u docs/multi-tenancy.md
("What this looks like on screen"):

- naziv organizacije kao prebacivač u zaglavlju + donji list (popis, nova, postavke)
- lokot na kartici privatnog projekta
- sekcija Tim = članovi organizacije (danas je unija svih projekata)
- kartica "Tim" u podnožju konačno vodi na ekran organizacije (sad je mrtva)
- gost NE vidi sekciju ni karticu Tim
- prekidač vidljivosti projekta (samo admin/owner)
  🟠 B20b. Dvije posljedice B12 u MemberDialogu, obje tihe:
  - postavke obavijesti smiju se mijenjati samo na VLASTITOM retku (politika + column grant),
    a sučelje ih još nudi na svakom članu → tuđi prekidač pada bez poruke
  - projectsStore.changeRole piše project_members.role, a UPDATE je grantom sužen na
    badge_enabled + notif_* → sada odbija. Treba RPC set_project_member_role uz provjeru
    can_manage_project_members, po istom obrascu kao org uloge iz B12.
    ⚠️ prije nego se dira MemberDialog.
    🔴 B20a. Popis kandidata za izvršitelja vuče se iz project_members (ItemListPanel), a to je
    nakon organizacija pogrešan izvor: na projektu vidljivom organizaciji ondje je samo tvorac,
    pa se ostalima ne može dodijeliti stavka iako imaju pristup. Kandidati moraju biti "tko ima
    pristup projektu" — org članovi za 'org', izričiti popis za 'private'.
    🟠 B20d. Popis članova znači različite stvari po vidljivosti, a sučelje ga prikazuje jednako:
  - 'org' → avatari i "dodaj člana" nemaju smisla (uvijek ista skupina) i zavaravaju, jer
    prikazuju samo one koji slučajno imaju redak. Maknuti, eventualno sitna oznaka vidljivosti.
  - 'private' → ostaju, i to je jedino mjesto gdje nose informaciju.
    🟠 B20e. Postavke obavijesti izvaditi iz MemberDialoga u postavke projekta. To je osobna
    postavka za projekt, a ne svojstvo retka u popisu ljudi — danas se nudi na svakom članu,
    što je i prije bilo pogrešno, a nakon B12 tuđe tiho padaju (vidi B20b).
    🟠 B20c. projectsStore.addMember traži profil po e-mailu i ubacuje redak u project_members.
    Nova politika to odbija ako osoba nije član organizacije — što je ispravno. Zamijeniti
    odabirom iz adresara organizacije; pozivanje izvana ide kroz pozivnice (B21).
    🟠 B21b. Stanje "nemaš pristup" na ProjectPage. Kad RLS ispravno ne vrati projekt, stranica
    se otvori prazna i bez naslova — izgleda kao kvar, a zapravo radi ispravno. Treba jasna
    poruka + povratak na Home. Uočeno pri testiranju B9–B11.
    🟠 B22. Badge preko organizacija: u aplikaciji samo tekuća, na ikoni zbroj svih, točkica na
    prebacivaču kad druga organizacija ima nepročitano. ⚠️ nakon B20.
    🟠 B23. Prvi ulazak: ako postoji pozivnica na taj e-mail → ulazi u tu organizaciju, inače se
    automatski stvori organizacija nazvana po korisniku. ⚠️ nakon B21 (pozivnice).
    🟠 B24. projects DELETE politika: sad samo autor. Dodati admin/owner organizacije — inače se
    ne može počistiti za članom koji je otišao.
    🟠 B21. Potvrda e-maila (G2) + pozivnice — **moraju ići zajedno**: bez potvrde e-maila se
    registriraš s tuđom adresom i preuzmeš tuđu pozivnicu.
    ✅ B25. (2026-08-11) project_members postaje pretplata, ne dozvola: nakon B7/B15 svaki
    član organizacije dobivao je obavijesti za SVAKI projekt vidljiv organizaciji, i za one
    koje nikad nije otvorio. auto_follow_on_message/_on_assign okidači + follow_project RPC
    (ručno) + unfollowProject (postojeća delete politika). _unread_rows i push_recipients
    vraćeni s LEFT na INNER JOIN na project_members.
    ⚠️ OVO IZGLEDA KAO PONIŠTAVANJE B15 — NIJE. B15: project_members kao provjera PRISTUPA
    (loše, curi/nedostaje pristup). Ovo: project_members kao provjera PRETPLATE, pristup i
    dalje zaseban can_access_project poziv u istom upitu. Pročitati komentar na vrhu
    20260811100000_project_following.sql prije nego se ovo dira.
    MessageInput.vue prikazuje dismissable notify ("Sada pratiš X — dobivat ćeš obavijesti",
    akcija Ne prati) kad je auto-praćenje upravo okinuto prvom porukom u projektu.
    🟢 B25b. Isti "sad pratiš" trenutak ne postoji za auto-praćenje preko dodjele stavke
    (auto_follow_on_assign) — korisnik dobije obavijesti bez ijedne poruke o tome. Manji
    prioritet: dodjela je rjeđi okidač i sam čin dodjele je već neka vrsta obavijesti.
    🟢 B25c. follow_project RPC nema još gumb u sučelju (ručno zapratiti projekt bez pisanja
    poruke) — čeka B20 (ekran/postavke projekta).

C. Baza — konzistentnost
🟠 C1. CHECK constrainti za preostale statusne kolone: project_members.role, push_tokens.platform, messages.channel. (items.kind/stage/priority ih imaju od M2.)
✅ C2. (2026-08-10) Atomarni create_project RPC — projekt + owner u jednoj transakciji. Uklonjena utrka i "projekt bez ownera"; usput jedini način da tvorac privatnog projekta uopće vidi ono što je upravo stvorio.
🟠 C3. Prijeći na inkrementalne migracije (svaka promjena = nova migracija; schema.sql ostaje kao dump referenca).
✅ C4. Drop legacy tablica bug_reads i idea_reads (riješeno 2026-08-09 uz M6).
✅ C5. Siročad u item_reads (riješeno 2026-08-09 uz M6 — tablicu je zamijenio item_user_state s pravim FK-om).
✅ C6. Brisanje screenshotova iz Storagea pri brisanju ideje/buga/TBI itema (riješeno 2026-08-05 — briše se i iz Storagea i iz lokalnog keša).

D. Performanse i skalabilnost
✅ D1. (2026-08-10) Server-side unread: get_unread() vraća gotove retke; klijent više ne dohvaća sve poruke. Pravilo "jedna stavka jedan badge" preseljeno u SQL (item_tab_new / item_tab_thread).
🟠 D2. Debounce/throttle fetchUnread() poziva (sad se zove nakon skoro svakog realtime eventa). Samostalno izvedivo i prije D1.
🟠 D3. Filtrirati realtime kanale za message UPDATE i message_reactions po project_id (sad slušaju sve projekte).
🟢 D4. Paginacija poruka u threadovima (sad se učitava cijeli thread; limit + "učitaj starije").
🟢 D5. Batch dohvat signed URL-ova za slike (sad jedan poziv po slici).

E. Testovi i kvaliteta
🟠 E1. Uvesti Vitest; prvi testovi za čistu logiku: threadKey(), unread agregacija i pravilo "jedna stavka jedan badge" (tabForNewItem/tabForThread), is_new pravila, prijelazi faza.
🟠 E2. GitHub Actions: lint:check + testovi na svaki push. ⚠️ nakon A2, E1.
🟠 E3. Ujednačen error handling: centralni wrapper oko store akcija + Quasar Notify za korisnika (sad greške uglavnom nestaju u konzoli). Konkretan primjer: `supabase.storage.from('chat-attachments').remove()` se poziva na više mjesta (brisanje buga/ideje/screenshota, uklanjanje avatara) i nigdje se ne provjerava vraćeni `error` — neuspjeh (npr. RLS odbije brisanje) prođe tiho, DB zapis se ažurira kao da je uspjelo, a objekt ostane sirotica u Storageu.
🟢 E4. Error reporting u produkciji (Sentry ili sličan).
🟢 E5. Playwright dim-test: login → kreiraj projekt → pošalji poruku → prihvati ideju.

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
🔴 L5. Android push NE RADI — nema google-services.json, pa build.gradle preskoči
google-services plugin i samo zapiše logger.info koji se u normalnom buildu ne vidi.
Provjeriti je li aplikacija com.vitka.collabapp uopće registrirana u Firebaseu, preuzeti
konfiguraciju u src-capacitor/android/app/ i rebuildati. Napomena: .gitignore ima tu
datoteku ZAKOMENTIRANU (redak 65) — nije ignorirana, samo nikad nije dodana. Kad se doda,
ograničiti Android API ključ po package name + SHA-1 (isto obrazloženje kao B0).
Usput ispraviti CLAUDE.md, koji tvrdi da Android push radi.
🟠 L6. Provjeriti POST_NOTIFICATIONS na Androidu 13+ — manifest deklarira samo INTERNET;
Capacitorov push plugin bi ga trebao ubaciti spajanjem manifesta, ali to se potvrđuje tek
na uređaju. ⚠️ nakon L5 (bez FCM-a se ionako nema što prikazati).
🟠 L7. Odvojiti aarcDev u vlastiti Firebase projekt. Sad dijeli projekt "sve-aplikacije" s
aplikacijama iz 2019., pa servisni račun firebase-adminsdk (čiji JSON je u Supabase
secrets) ima administratorska prava nad svime, ne samo nad aarcDev-om. Manji doseg,
odvojene kvote, lakše predati dalje. ⚠️ prije javnog izlaska.
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
✅ M3. (2026-08-08) messages.item_id umjesto tri nullable FK-a; prevezivanje poruka preko mape (spaja
threadove spojenih parova). Usput otpada COALESCE unique indeks i prisila na
upsert_message_read RPC (invarijanta 3 u CLAUDE.md).
✅ M4. (2026-08-08) Storovi: ideas/bugs/tbi → jedan items store. fetchUnread se bitno pojednostavljuje.
✅ M5. (2026-08-08) Sučelje: kartice filtriraju po kind/stage, radnje Prihvati/Odbij umjesto promoviraj,
oznaka "Pratim" (oko) + filtar po njoj, sortiranje po priority.
✅ M6. (2026-08-09) Brisanje starih tablica (ideas, bugs, tbi_items, item_reads), viewa
thread_message_counts i privremene mape. ⚠️ tek kad M3–M5 rade.
✅ M7. (2026-08-09) Usklađena dokumentacija nakon M6: CLAUDE.md invarijante 3, 4 i 8, docs/database.md,
docs/workflows.md (tvrdi da lista ideja prikazuje i promovirane — kod to ne radi).

Preporučeni redoslijed ako želiš vodilju
Odmah, prije bilo čega: A1–A2 (git), zatim B1–B3 (RLS).
Sljedeći sloj: C2 (atomarni createProject), D1–D3 (unread + kanali), E1–E3.
Zatim po volji — sve ostale točke su međusobno uglavnom neovisne; ovisnosti su označene na točkama.
Reci ako želiš da neku točku razradim u detaljnu specifikaciju (npr. B1 — popis konkretnih politika po tablici, ili D1 — dizajn unread RPC-a).
