aarcDev — Backlog razrađen u samostalne točke
Organizirano po temama, ne po mjesecima — svaka točka je samostalan zadatak koji možeš uzeti kad želiš. Oznake: 🔴 kritično, 🟠 važno, 🟢 kad stigneš. Gdje postoji ovisnost, piše "⚠️ nakon".

A. Git i higijena projekta
✅ A1. Napraviti pravi inicijalni commit postojećeg stanja (riješeno 2026-08-08, commit c1d4857).
✅ A2. Postaviti remote repozitorij (GitHub) i push (riješeno 2026-08-08, https://github.com/alvsky/aarcDev).
✅ A3. (2026-08-11) Dogovoren workflow. `feature/item-model` je davno prestala biti "jedan
feature" (42 commita, sav stvaran rad zadnjih dana) dok je `main` stajao zamrznut od 8.8. —
spojeno (fast-forward) u main, stara grana obrisana. Ubuduće: kratkotrajne grane po
zadatku/BACKLOG točki (`feature/<kratko-ime>` ili `fix/<kratko-ime>`), granane iz main-a,
spojene i obrisane čim taj zadatak radi — ne ostaviti granu da živi tjednima i prikupi
nepovezane promjene. main ostaje uvijek buildabilan; veći/rizičniji rad (poput multi-tenancy
migracije) i dalje ide na svoju granu dok se ne potvrdi da radi.
✅ A4. Obrisati mrtve datoteke (riješeno 2026-08-08, commit df0f18c): BugCard-copy.vue, app-copy.scss, router/index-copy.js, example-store.js, src/i18n/en-US/. IndexPage.vue i SecondPage.vue su već obrisani.
🟢 A5. Ukloniti debug console.log iz storova i stranica (chat edit, project delete, demote, push flow, kompresija slika).

B. Sigurnost — migracija na višenajamnost (RLS)
Model i obrazloženje: docs/multi-tenancy.md. **Redoslijed nije proizvoljan** — backfill mora
proći prije nego politike postanu stroge, inače si zaključaš vlastite podatke. Sve ide kao
inkrementalne migracije (vidi C3), ne kao ručne izmjene u dashboardu.

Priprema
✅ B0. (2026-08-11) Ograničen Firebase iOS API ključ (Google Cloud Console → Application
restrictions → iOS apps → bundle ID com.vitka.collabapp; API restrictions → samo Firebase
Cloud Messaging API, Firebase Installations API, FCM Registration API — sve ostalo isključeno,
npr. Firebase In-App Messaging koje app ne koristi). GitHub secret scanning alert
(GoogleService-Info.plist) treba još ručno zatvoriti kao "won't fix" u Security tabu (klijentska
konfiguracija, ne tajna — rotacija nema smisla, ograničenje ključa je stvarna mjera). Isti
postupak vrijedi za Android ključ kad L5/L7 dođu na red.
⚠️ Bitnije od toga: Supabase anon ključ je jednako javan i bezopasan SAMO ako RLS radi —
danas ne radi, što je razlog za ostatak ove sekcije.
✅ B1. (2026-08-10) Snimka baze prije početka. RLS promjene tiho lome realtime (realtime poštuje RLS) i nema
ih se lako vratiti unatrag. ⚠️ vidi F2 — idealno na staging okolini prvo.
✅ B2. (2026-08-11) Auth postavke iz dashboarda u config.toml: project_id, site_url
(vitkadesign.com/aarc.html — statična potvrdna stranica, vidi G2), additional_redirect_urls
(namjerno prazno — ista stranica za svaku okolinu, ne treba unos po localhost/prod/mobitel),
jwt_expiry (3600), enable_confirmations (uključeno 2026-08-11, ranije isključeno zbog limita
besplatnog plana). ⚠️ minimum_password_length i rate limiti NISU potvrđeni s dashboarda —
ostavljeni na CLI defaultu (6), označeno komentarom u datoteci. Zapis sam po sebi ne mijenja
živi projekt (treba eksplicitni `supabase config push`).

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
✅ B16. (2026-08-10) Storage: politike u migraciju
(supabase/migrations/20260814100000_storage_policies.sql). Nova putanja
chat-attachments/${projectId}/${userId}/${uuid}.jpg — RLS napokon može provjeriti
can_access_project(projectId) (stara putanja bez projekta to nije dopuštala); INSERT/DELETE
traže vlastitu podmapu. Avatari preseljeni u zaseban avatars bucket, ${userId}/${uuid}.jpg,
vidljivost prati can_see_profile (isto pravilo kao profiles_select) umjesto da dijele
bucket/politike s chat prilozima. Oba bucketa dobila file_size_limit + allowed_mime_types
(image/jpeg — jedino što compressImage ikad proizvede). ⚠️ SVJESNO bez migracije postojećih
objekata — dev okruženje, prihvaćen prekid (stari screenshotovi/avatari mogu postati
nedostupni dok se ponovno ne uploadaju; retci u bazi nisu dirani). useImageUpload.js sad prima
bucket/pathPrefix; svi pozivatelji (MessageInput, ItemDialog, ProfilePage) ažurirani.

Provjera
🟡 B17. (2026-08-10, trenutno ne prolazi) Testovi izolacije: korisnik A ne vidi ništa iz
organizacije korisnika B. ⚠️ Otkad je "Confirm email" uključen (2026-08-11, B2/G2)
`tests/helpers.js#createTestUser` više ne dobiva sesiju odmah nakon `signUp()` pa test puca.
Pravo rješenje: service_role Admin API (`createUser({ email_confirm: true })`) za test
korisnike, zaobiđe potvrdu SAMO za njih. Odgođeno na izričit zahtjev — vratiti se uz G2.
Vitest uveden (E1 dobio infrastrukturu, ali ne i planirane unit testove čiste logike — to je
zaseban zadatak). tests/helpers.js (izolirani klijent po test korisniku, bez localStora u
Node-u, best-effort čišćenje brisanjem organizacije — org_id/project_id FK-ovi su ON DELETE
CASCADE pa se povlači sve) + tests/rls-isolation.test.js: dvije potpuno odvojene
org/korisnika, 14 provjera iz kuta korisnika B (liste, izravan .eq('id'), update/delete/insert,
profiles, org_members, invitations, set_project_member_role/remove_org_member RPC-ovi) + jedna
kontrolna da vlasnik i dalje vidi vlastito. `pnpm test`. Integracijski protiv pravog dev
Supabase projekta (⚠️ ne lokalni — nema Dockera/supabase start u repou), pa svako pokretanje
stvori i obriše prave test korisnike/organizacije ondje.
🔴 B18. Regresija nakon zatezanja: manual profile joins, realtime događaji, item_message_counts
view (security_invoker — mijenja se ponašanje kad politike postanu stroge!), edge funkcija
(service role zaobilazi RLS — OK), offline keš.
🟠 B19. delete_own_account(): provjera zadnjeg vlasnika JE od B13 na poslužitelju (okidač
odbija kaskadno brisanje zadnjeg vlasnika). Preostaje samo da aplikacija tu iznimku uhvati i
pokaže čitljivu poruku umjesto sirove Postgres greške.

Sučelje (nakon što baza stoji)
✅ B20. (2026-08-11) Home i ekran organizacije, po specifikaciji u docs/multi-tenancy.md
("What this looks like on screen"): naziv organizacije kao prebacivač u zaglavlju (donji
list: popis organizacija s bedžom nepročitanog, "Nova organizacija", "Postavke organizacije")

- nova stranica OrgPage (preimenovanje, popis članova s ulogama, promjena/oduzimanje uloge,
  uklanjanje člana, prijenos vlasništva, napusti organizaciju, opasna zona brisanja) + lokot na
  kartici privatnog projekta + Tim sekcija sad je org roster, ne unija project_members + kartica
  "Tim" u podnožju konačno vodi na /org (bila je mrtva) + gost ne vidi Tim ni FAB za novi
  projekt + prekidač vidljivosti u ProjectDialogu (samo admin/owner, samo pri uređivanju — novi
  projekt je uvijek privatan). Nove RPC/politike: create_organization,
  organizations_update/delete. Usput otkriven i popravljen mrtav realtime na Homeu:
  useRealtime dobiva onIdea/onBug koje composable ne prepoznaje otkad postoji items (M2/5a) —
  otad je realtime za stavke na Homeu bio tih; sad onItem.
  ✅ B20a. (2026-08-11) Kandidati za izvršitelja sad ovise o vidljivosti: org roster
  (orgsStore.fetchMembers, bez gostiju) za 'org', project_members za 'private' (ondje redak
  i dalje = dozvola, ne samo pretplata).
  ✅ B20d. (2026-08-11) Avatari na kartici projekta i Tim sekcija sad koriste org roster za
  vidljivost 'org' (isto rješenje kao B20a), project_members samo za 'private'. Lokot iz istog
  prolaza.
  ✅ B20b. (2026-08-12) Prilikom pregleda ispalo je da prekidač obavijesti nije bio bug —
  već je bio ograničen na `v-if="member.user_id === authStore.user?.id"`, samo je backlog
  zapis bio netočan. Pravi problem: projectsStore.changeRole je pisao project_members.role,
  a UPDATE je grantom sužen na badge_enabled/notif\_\* (B12) → tiho odbijao. Zamijenjen
  RPC-om set_project_member_role uz can_manage_project_members provjeru, isti obrazac kao
  org uloge iz B12. Stari changeRole obrisan (bio je mrtav kod — nigdje pozvan).
  ✅ B20e. (2026-08-12) Postavke obavijesti sad se prikazuju samo kad postoji
  myMembership (stvarna pretplata), odvojeno od popisa članova — vrijede neovisno o
  vidljivosti projekta.
  ✅ B20c. (2026-08-12) addMember (po e-mailu) zamijenjen s addProjectMember(projectId,
  userId): biranje iz adresara organizacije (orgsStore.members, uključujući goste — to je
  jedini način da gost dobije pristup) umjesto upisivanja e-maila koji politika svejedno
  odbija ako osoba nije član organizacije. Riješeno zajedno s B20b/B20e kroz cijeli
  MemberDialog — dijalog sad razlikuje 'org' (samo objašnjenje + vlastite postavke, popis
  je otkad B25 samo pretplata, ne pristup) od 'private' (stvaran popis + upravljanje).
  ✅ B21b. (2026-08-11) Stanje "nemaš pristup" na ProjectPage — loading spinner pa jasna
  poruka + povratak na Home, umjesto prazne stranice bez naslova.
  ✅ B22. (2026-08-11) Badge preko organizacija: točkica na prebacivaču kad druga organizacija
  ima nepročitano (notifStore.orgUnread). Badge na ikoni aplikacije je zbroj svih organizacija
  otkad postoji — fetchUnread/syncBadge nikad nisu filtrirali po organizaciji, samo po
  RLS-vidljivim projektima.
  ✅ B23. (2026-08-10) Prvi ulazak: LoginPage.submit() nakon uspješne registracije provjerava
  je li redirect `/invite/:token` (dolazi preko pozivnice — accept_invitation na
  AcceptInvitePage će stvoriti članstvo poslije ovog redirecta) i SAMO ako nije, zove
  orgsStore.createOrg(form.fullName) — nova organizacija nazvana po punom imenu, s
  korisnikom kao ownerom (create_organization RPC, isti obrazac kao create_project).
  ✅ B24. (riješeno ranije, uz B9–B11 — backlog samo nije bio ažuriran) projects DELETE:
  is_org_admin(org_id) or created_by = auth.uid().
  ✅ B21. (2026-08-13, potvrđeno 2026-08-10) Pozivnice IZGRAĐENE, svjesno prije G2 — na izričit
  zahtjev, prihvaćen rizik za mali povjerljivi tim. get_invitation_preview RPC (novi,
  anon+authenticated: pregled bez prijave preko tokena) + OrgPage obrazac za slanje/povlačenje +
  kopirljiv link (`/#/invite/:token`, nema slanja e-mailova — K4) + AcceptInvitePage (grana na
  neprijavljen/kriva adresa/ispravna adresa) + LoginPage `redirect`+`email` query da token
  preživi prijavu/registraciju. End-to-end potvrđeno s pravim računom (registracija preko
  invite linka → ulazak u "vitka d.o.o." kao member).
  🔴 PRIJE JAVNOG IZLASKA: bez G2 se netko može registrirati tuđom (nepotvrđenom) adresom i
  preuzeti tuđu pozivnicu — accept_invitation uspoređuje e-mail sesije s pozivnicom, ali ta
  provjera vrijedi onoliko koliko vrijedi da je adresa stvarno vlasnikova. Zatvoriti s G2 prije
  javnog izlaska, ne odgađati dalje.
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
🟠 G2. Email verifikacija pri registraciji. Djelomično: "Confirm email" ponovno uključen u
dashboardu 2026-08-11 (config.toml, vidi B2), statična potvrdna stranica na
vitkadesign.com/aarc.html. LoginPage.vue popravljen (2026-08-11) da ne pretpostavlja sesiju
odmah nakon signUp() — provjerava `session`, prikazuje "provjeri email" umjesto pucanja na
createOrg/redirectu. Gmail custom SMTP isprobano i ODBAČENO 2026-08-11 — vraća 500 na
signUp (razlog nije do App Passworda, do same Gmail SMTP prirode za transakcijski mail, Supabase
i sam upozorava "designed for personal rather than transactional"); ugrađeni Supabase mailer
radi ispravno i za sad je dovoljan. Pravi SMTP servis (Postmark/Resend i sl.) treba tek pred
javni izlazak. Preostaje: `emailRedirectTo` eksplicitno pri signUp() (trenutno oslonjen na
Site URL default — dovoljno dok postoji samo jedna potvrdna stranica). B17 testovi trenutno ne
prolaze zbog ovoga (vidi B17).
🟢 G3. Transfer ownershipa projekta (UI + pravila; preduvjet za elegantno brisanje računa).
✅ G4. Upload avatara (riješeno 2026-08-07) — UserAvatar komponenta (foto ili inicijali, skalira s postavkom veličine teksta preko --aarc-font-scale), upload/promjena/uklanjanje na Profilu, avatar_url dodan u sve profile select()-e i zamijenjeno svih 6 mjesta prikaza (MessageList, MemberDialog, ProjectsPage ×3, ProfilePage).

H. Suradnja i onboarding
🟠 H1. Invite flow: pozivnica emailom/linkom, pending stanje, prihvat nakon registracije (sad član mora već imati račun).
🟢 H2. Notifikacija "dodan si u projekt".
🟢 H3. Per-user postavke notifikacija finije od badge_enabled (npr. samo mentioni, samo threadovi u kojima sudjelujem).
✅ H4. (2026-08-11) Statistika po članu organizacije na OrgPage. Nova RPC org_member_stats
(20260814150000_org_member_stats.sql) — SAMO owner (RPC sama baca ako nisi, ADMIN namjerno
isključen za sad — može se proširiti kasnije po potrebi), agregira po korisniku: broj
projekata u kojima je aktivan (prijavio nešto ili mu je nešto dodijeljeno — ne project_members,
to je od B25 pretplata, ne aktivnost), broj prijavljenih ideja/bugova/zadataka, broj
dodijeljenih stavki. Toggle gumb "Statistika" u zaglavlju popisa članova (vidljiv samo owneru),
dohvat lijen (tek na klik). Ostali članovi i dalje vide samo osnovne podatke
(avatar/ime/email/uloga) kao i prije.

I. Navigacija i UX
✅ I1. (2026-08-10) Router refaktor: tabovi u URL-u. Jedna ruta
`/project/:id/:tab(chat|bugs|ideas|tbi)?` (zamijenila neiskorištene djecu-rute — ProjectPage i
dalje sam crta q-tabs + keep-alive panele, isti razlog kao prije: gubitak keep-alivea preko
pravog nested router-viewa nije vrijedio prepravke; ovo samo čini tab dijelom adrese). ProjectPage
`tab` je sad writable computed nad `route.params.tab` (get) / `router.replace` (set, ne push —
tab-switch ne buši povijest). Thread/kanal u URL-u kroz `?item=`/`?channel=` query — ItemListPanel
i ChatPage ih čitaju pri mountu i odmah briše (router.replace) čim potroše. Usput POJEDNOSTAVLJEN
I2: `notifStore.pendingDeepLink` (privremeno rješenje dok I1 nije postojao) uklonjen —
usePush.js sad gradi URL izravno (`router.push({ path, query })`).
✅ I2. (2026-08-10, pojednostavljeno nakon I1) Push notifikacija otvara konkretan
projekt/thread. pushNotificationActionPerformed (usePush.js) čita payload (projectId +
itemId/kind ili channel) i pozove router.push na `/project/:id/:tab?item=`/`?channel=`.
ItemListPanel otvara ThreadDialog čim stavka stvarno stigne u (već po vrsti filtriran)
items prop, ChatPage čita ?channel pri mountu — oba brišu query čim ga potroše. (Prvotna
verzija je ovo rješavala preko privremenog notifStore.pendingDeepLink jer I1 još nije
postojao; maknuto kad je I1 stigao.)
🟢 I3. Offline UX: indikator mreže, disable slanja bez mreže, queue za neposlane poruke.
✅ I4. (2026-08-11) Loading/skeleton stanja umjesto praznih lista tijekom fetcha. Novi
loading/isLoading getteri u projects/items/chat storovima — namjerno samo dok je popis STVARNO
prazan (prvi fetch bez keša), ne na svaki refetch, jer su sva tri storea persistana pa bi
skeleton preko već prikazanog keširanog sadržaja samo treperio bez svrhe. q-skeleton redci na
Homeu (projekti), ItemListPanel (ideje/bugovi/tbi) i MessageList (chat, novi `loading` prop kroz
ChatPanel).
✅ I5. (2026-08-11) Potvrdni dijalozi ujednačeni. Svih 8 mjesta (item/projekt/poruka/organizacija
član/vlasništvo/napuštanje/brisanje/pozivnica) već je vizualno bilo identično (title/message/ok
crveno/cancel) — pravi problem je bio kopipejstan blok na 8 mjesta, ne nedosljednost. Novi
useConfirmDialog.js#confirmDestructive vraća Promise<boolean> umjesto .onOk() callbacka
(`if (!(await confirmDestructive({...}))) return`), jedno mjesto umjesto osam.
✅ I8. (2026-08-11) Prikvačeni projekti na Homeu. Nova tablica project_user_state
(supabase/migrations/20260814120000_project_pins.sql) — isti obrazac kao item_user_state
("Pratim"): osobno, po korisniku, odvojeno od project_members jer taj redak (otkad je B25
pretplata) ne postoji za svaki projekt kojem korisnik ima pristup. Prikvačeni uvijek na vrhu
popisa, neovisno o odabranom sortiranju (nepročitano/naziv) — to mu je i svrha. Toggle iz
"more" izbornika na kartici projekta.
🟢 Ideja za kasnije (zapisano 2026-08-11, NE raditi sad): pravi drag-and-drop (slobodan
redoslijed, ne samo prikvačeno/ne) — razmatrano kao mogući premium/plaćeni feature ako app
ikad dobije komercijalne pakete pretplate. **I8 (Prikvačeno) je već izgrađen i dostupan svima
(2026-08-11)** — potvrđeno da je namjera da se ONO, kad tierovi jednog dana postoje, premjesti
iza premium provjere zajedno s drag-and-dropom, ne da ostane besplatno zauvijek.
🟢 Ideja za kasnije (zapisano 2026-08-11, NE raditi sad, ista kategorija — mogući
premium/plaćeni feature): cropper za avatar prije uploada (drag/zoom unutar kružnog okvira,
canvas crta poziciju koju korisnik odabere prije kompresije u useImageUpload.js — ne treba
nova biblioteka, isti canvas pipeline). Trenutno object-fit:cover reže simetrično oko centra
FOTOGRAFIJE, ne oko motiva — ako motiv nije centriran na originalnoj slici, izrezan krug to
neće ispraviti. Glavni trošak je touch drag/pinch-zoom UI na mobitelu, ne sama logika.
✅ I7. (2026-08-11) Pretraga i sortiranje na Homeu — sort gumb uvijek vidljiv čim ima ijedan
projekt (korisno znati poredak i s par projekata), tražilica se pojavljuje tek s >5 projekata
(kod par projekata samo šum). Filtrira po nazivu, sort prebacuje nepročitano-prvo ↔ abecedno.
✅ I6. (2026-08-11) UserAvatar centriranje — pravi uzrok NIJE bio font/box-centriranje inicijala
(sve ranije teorije/zakrpe bile su pogrešan trag), nego `border` na `.profile-avatar`
(ProfilePage.vue): pravi border ulazi u box-model i remeti Quasarov interni
`width/height: inherit` lanac unutar q-avatara (`.q-avatar__content`/`img` prestanu biti točno
100%×100% centrirani). Zamijenjen `box-shadow` prstenom iste boje — čisto vizualan, ne dira
dimenzije. Usput očišćen UserAvatar.vue natrag na goli Quasar (uklonjeni glyphSize/font-size
prop, `.avatar-initials` span/CSS, `object-position`/`width`/`height` override na img — ništa
od toga nije bilo pravi uzrok, samo šum) — ostavljen samo `object-fit: cover` (jedino što
Quasar stvarno ne postavlja sam, bez njega bi se pravokutna slika razvukla).
✅ I9. (2026-08-11) Reveal + clear na password poljima, clearable na tekstualnim poljima kroz
app. Profile promjena lozinke (3 polja) dobila oko-ikonu (isti obrazac kao LoginPage), sva tri
+ `clearable`. `clearable` dodan i na: LoginPage (ime/email/lozinka), ProjectDialog
(naziv/opis), ItemDialog (naslov), OrgPage (invite email). Namjerno preskočeno: chat composer
(MessageInput) i inline uređivanje poruke (MessageList) — X gumb bi ondje samo smetao uz
postojeći tok (autogrow, slanje na Enter).

J. TBI modul — proširenja
🟢 J1. Due date + sortiranje po prioritetu/roku.
🟢 J2. Filteri: po assigneeu, statusu, izvoru (getteri byStatus/bySource već postoje).
🟢 J3. Kanban pogled po statusu (razmisliti o proširenju statusa: tbi → in-progress → done).
🟢 J4. Notifikacija assigneeu kad mu se dodijeli item.

K. Chat — proširenja
🟢 K1. Push i za nove ideje/bugove/TBI iteme (sad samo poruke okidaju edge function).
🟢 K2. Mention (@ime) + push na mention.
✅ K3. (2026-08-11) Pretraga stavki i poruka — nova ProjectSearchDialog.vue (ikona u zaglavlju
projekta). Stavke: klijentska pretraga po naslovu/opisu preko itemsStore.byProject — namjerno
SVE faze uključujući gotovo/odbijeno (svrha je "je li ovo već bilo?", ne samo aktivan rad).
Poruke: OPCIONALNO (checkbox, zadano isključeno) — chatStore.searchMessages, obična ILIKE
(ne pravi Postgres FTS/tsvector) jer se rezultati ne pamte u stateu i pretraga ide tek na
eksplicitan upit — sken bez indeksa prihvatljivo "jeftin" za sad; nadograditi na pravi FTS
ako ikad postane sporo na pravom volumenu. Klik na rezultat vodi na točan tab/thread/kanal
kroz isti query-param mehanizam kao I1/I2 (`?item=`/`?channel=`). Dijakritika (2026-08-11):
src/utils/text.js#normalizeSearch (NFD + skidanje kombinirajućih znakova) za klijentsku
pretragu stavki I Home popisa projekata; poruke idu preko nove search_messages RPC funkcije
(20260814130000_search_unaccent.sql, unaccent ekstenzija) jer supabase-js .ilike() ne zna
omotati stupac u SQL funkciju. Usput popravljen manji gap iz
I1/I2: ChatPage je ?channel= čitao samo jednom pri mountu — kod keep-alive ponovne aktivacije
(korisnik već bio na chatu, pa se vrati preko pretrage/notifikacije na drugi kanal) to se
gubilo; sad se čita i u onActivated.
Popravci nakon prijavljenog problema (2026-08-11): tabForItem je gledao je li stavka TRENUTNO
na TBI ploči (accepted_at) umjesto stvarne domene pogleda — gotova ideja koja je nekad bila
prihvaćena znala je završiti na TBI-u gdje zatvoreno po zadanom ostaje skriveno. Sad se tab
bira izravno iz kind/stage (task ili aktivna faza → tbi, inače matični pogled). ItemListPanel
"visible" filter sad uvijek forsira vidljivost cilja deep-linka (highlightItemId), mimo
showClosed/onlyWatching. ItemCard dobio "expanded" prop — kartica se sama otvori
(q-expansion-item v-model) i skrola u prikaz čim je cilj deep-linka, umjesto da se automatski
otvara ThreadDialog (chat) preko nje. Search dijalog čisti svoje polje/checkbox/rezultate čim
se zatvori (klik na rezultat ili ručno zatvaranje), ne ostaje zaglavljen s prošlim upitom.
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
🟢 L8. (zapaženo 2026-08-10 tijekom I2 testiranja) Broj na ikonici aplikacije uz Xcode-debug
build ne ažurira se dok je app u pozadini/zatvorena — vidljiv tek nakon otvaranja appa (JS
`notifStore.syncBadge()` preko @capawesome/capacitor-badge). Push payload nosi i nativni
`apns.payload.aps.badge` koji bi iOS trebao primijeniti sam bez appa; postavke uređaja
(Settings → Notifications → Badges) potvrđeno uključene, pa uzrok vjerojatnije Xcode-debug
kvirka nego stvarni bug. Provjeriti na pravoj instalaciji (TestFlight/ad-hoc, ⚠️ nakon L2) prije
nego se ovo tretira kao pravi zadatak za popraviti.
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

N. Bugovi — proširenja
✅ N1. (2026-08-11) Platforma kod prijave buga. Nova kolona `items.platform` (text, CHECK
ios/android/web — items već lomi "bez CHECK-a" konvenciju za vlastiti rječnik, isti obrazac
ovdje). ItemDialog.vue: q-select vidljiv samo za kind='bug', pri stvaranju novog buga
unaprijed popunjen preko `Capacitor.getPlatform()` (na webu vraća 'web', poklapa se s
CHECK-om), korisnik ga može promijeniti. ItemCard.vue prikazuje malu ikonu
(phone_iphone/android/public) uz prioritet/fazu, samo kad je platforma poznata.

Preporučeni redoslijed ako želiš vodilju
Odmah, prije bilo čega: A1–A2 (git), zatim B1–B3 (RLS).
Sljedeći sloj: C2 (atomarni createProject), D1–D3 (unread + kanali), E1–E3.
Zatim po volji — sve ostale točke su međusobno uglavnom neovisne; ovisnosti su označene na točkama.
Reci ako želiš da neku točku razradim u detaljnu specifikaciju (npr. B1 — popis konkretnih politika po tablici, ili D1 — dizajn unread RPC-a).
