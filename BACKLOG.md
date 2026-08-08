aarcDev — Backlog razrađen u samostalne točke
Organizirano po temama, ne po mjesecima — svaka točka je samostalan zadatak koji možeš uzeti kad želiš. Oznake: 🔴 kritično, 🟠 važno, 🟢 kad stigneš. Gdje postoji ovisnost, piše "⚠️ nakon".

A. Git i higijena projekta
✅ A1. Napraviti pravi inicijalni commit postojećeg stanja (riješeno 2026-08-08, commit c1d4857).
🔴 A2. Postaviti remote repozitorij (GitHub) i push.
🟠 A3. Dogovoriti granu-po-featureu workflow (main uvijek buildabilan).
🟢 A4. Obrisati mrtve datoteke: ChatPage-copy.vue, LoginPage8.vue, BugCard-copy.vue, app-copy.scss, router/index-copy.js, example-store.js, IndexPage.vue, SecondPage.vue, src/i18n/en-US/. ⚠️ nakon A1 (da postoji povijest).
🟢 A5. Ukloniti debug console.log iz storova i stranica (chat edit, project delete, demote, push flow, kompresija slika).

B. Sigurnost (RLS i podaci)
🔴 B1. Napisati popis ciljanih RLS pravila po tablici (spec, ne kod): ideje/bugovi/tbi/poruke → is_member(project_id) za SELECT/INSERT/UPDATE; profili → vidljivi samo sučlanovima.
🔴 B2. Primijeniti nove RLS politike na staging pa na produkciju. ⚠️ nakon B1 i F2 (staging).
🔴 B3. Verificirati da nakon RLS-a i dalje rade: manual profile joins, realtime eventi (realtime poštuje RLS!), thread_message_counts view, edge function (service role zaobilazi RLS — OK).
🟠 B4. project_members: INSERT/UPDATE ograničiti na ownera (sad "anyone").
🟠 B5. Server-side guard za brisanje računa (sole-owner provjera u delete_own_account() — sad je samo klijentski).
🟢 B6. Pregledati Storage pravila za chat-attachments (tko smije upload/delete u tuđe puteve).

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
Preporučeni redoslijed ako želiš vodilju
Odmah, prije bilo čega: A1–A2 (git), zatim B1–B3 (RLS).
Sljedeći sloj: C2 (atomarni createProject), D1–D3 (unread + kanali), E1–E3.
Zatim po volji — sve ostale točke su međusobno uglavnom neovisne; ovisnosti su označene na točkama.
Reci ako želiš da neku točku razradim u detaljnu specifikaciju (npr. B1 — popis konkretnih politika po tablici, ili D1 — dizajn unread RPC-a).
