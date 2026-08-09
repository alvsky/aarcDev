# Offline-first Razina 1 + queue za poruke — specifikacija

> **Status: implementirano 2026-08-05** (točke 1–5; točka 6 `client_id` zaštita od duplikata
> ostaje opcionalna). Ovaj dokument je sada referenca dizajna implementiranog sustava.

Cilj: aplikacija se otvara **odmah** sa zadnjim poznatim stanjem (bez čekanja mreže), offline
se sve može **čitati**, a poruke napisane bez mreže čekaju u queueu i šalju se automatski kad
se veza vrati. Sve postojeće ponašanje (fetch na mount, realtime write-echo, unread logika)
ostaje netaknuto — perzistencija je sloj **ispod** postojećih storova, ne zamjena.

Izvan opsega (namjerno): offline uređivanje/brisanje/reakcije, offline kreiranje itema,
slanje slika offline, delta sync (`updated_at` kursori — to je Razina 2), rješavanje konflikata.

## 0. Preduvjeti / odluke

- **Nova ovisnost: `localforage`** (IndexedDB wrapper, ~8 kB, bez native koda — radi u WebViewu
  na iOS/Android i na webu). localStorage nije opcija: limit ~5 MB i sinkroni API.
  ⚠️ AI_RULES traži odobrenje za nove ovisnosti — **potvrdi prije početka**.
  Alternativa bez ovisnosti: ručni IndexedDB wrapper (~60 linija), ali localforage je robusniji.
- Detekcija mreže: browser `online`/`offline` eventi + `navigator.onLine` (rade u Capacitor
  WebViewu). Bez Capacitor Network plugina za sada — može se dodati kasnije ako se pokaže
  nepouzdano na uređajima.
- Sav keš je **po korisniku** (ključ uključuje `user.id`) i briše se pri odjavi — dva računa
  na istom uređaju ne smiju vidjeti tuđi keš.

## 1. Sloj perzistencije — `src/utils/persistence.js`

Mali modul (bez Vue ovisnosti) oko localforage:

- `persistKey(userId, slice)` → `aarc:${userId}:${slice}` (npr. `aarc:<uid>:chat`)
- `saveState(userId, slice, data)` — debounce 500 ms po sliceu (da tipkanje/realtime ne
  mlati disk); serijalizira JSON-safe kopiju
- `loadState(userId, slice)` → objekt ili `null`
- `clearAll(userId)` — briše sve sliceove korisnika (poziva se iz `logout` i `deleteAccount`)
- `SCHEMA_VERSION` konstanta zapisana uz svaki slice; pri učitavanju, ako se verzija ne
  poklapa → keš se odbacuje (štiti od promjena oblika state-a u budućim verzijama)

## 2. Pinia plugin — `src/stores/persist-plugin.js`

Registrira se u `src/stores/index.js` (`pinia.use(...)`). Za svaki store s
`persist: ['polje1', ...]` opcijom u definiciji:

- nakon prijave (auth store javi userId) → napuni navedena polja iz lokalne pohrane **ako su prazna**
- `store.$subscribe` → debounced `saveState` samo navedenih polja

Storovi i polja koja se perzistiraju:

| Store         | Polja      | Napomena                                                              |
| ------------- | ---------- | --------------------------------------------------------------------- |
| projects      | `projects` |                                                                       |
| ideas         | `ideas`    |                                                                       |
| bugs          | `bugs`     |                                                                       |
| tbi           | `items`    |                                                                       |
| chat          | `threads`  | najveći slice; v1 bez rezanja, kasnije zadnjih ~200 poruka po threadu |
| notifications | `unread`   | badge odmah točan pri otvaranju                                       |

Auth store se NE perzistira ovim mehanizmom (session već čuva supabase-js u localStorage;
lang/darkMode/fontSize već imaju vlastiti localStorage).

**Učitavanje iz lokalne pohrane + postojeći fetch = "prvo staro, pa svježe" bez dodatnog
koda:** stranice već zovu `fetchX()` u `onMounted`; spremljeno stanje se prikaže odmah, fetch ga zamijeni kad
stigne (postojeći merge `[...filter(!pid), ...mapped]` to već radi ispravno). Jedina
promjena u storovima: dodati `persist` opciju — akcije se ne diraju.

## 3. Mrežni status — `src/composables/useNetwork.js`

- `online` ref (init iz `navigator.onLine`), listeneri na `window` `online`/`offline`
- `onReconnect(cb)` — callback pri prijelazu offline→online
- Modul-scope singleton (kao `usePush` pending token) da svi potrošači dijele isto stanje

UI (minimalno, v1):

- `MainLayout.vue` / `ProjectPage.vue`: tanka traka "Nema veze — prikazujem spremljene
  podatke" kad je offline (i18n: `common.offline`)
- `MessageInput.vue`: gumb za prilog (sliku) disabled offline (slike se ne queueaju u v1)

## 4. Queue za poruke (outbox) — u `chat.js` storu

Novo state polje `outbox: []` (perzistira se u `chat` slice). Stavka:

```
{ tempId, projectId, ideaId, bugId, tbiId, channel, body, replyToId,
  createdAt, attempts, lastError }
```

Ponašanje:

- **`sendMessage`**: ako je offline ILI insert padne zbog mrežne greške (fetch error, ne
  Postgres greška!) → stavka ide u `outbox`, a u `threads[key]` se odmah doda **optimistična
  poruka** (`id: tempId`, `pending: true`, profil = trenutni korisnik). Postgres greške
  (RLS, constraint) se i dalje bacaju kao danas — te ne idu u queue.
- **`flushOutbox()`**: šalje stavke redom (FIFO); uspjeh → makni iz outboxa i makni
  optimističnu poruku (realtime echo donosi pravu — postojeći dedup po id-u ostaje);
  mrežni neuspjeh → prekini flush (pokušat će opet na sljedeći trigger), `attempts++`.
  Guard protiv paralelnih flusheva (`flushing` flag).
- **Triggeri za flush**: `onReconnect`, povratak aplikacije u foreground (postojeći
  `appStateChange` listener u `App.vue`), nakon prijave, i nakon svakog uspješnog
  `sendMessage` (ako outbox nije prazan).
- **UI pending poruke** (`MessageList.vue`): smanjeni opacity + ikonica sata; long-press na
  pending poruku nudi samo "Obriši" (= makni iz outboxa, bez potvrde prema bazi).
  Nakon npr. 5 neuspjelih pokušaja → ikonica upozorenja + akcija "Pokušaj ponovno".
- **Dedup rizik** (poslano, ali odgovor izgubljen → retry = duplikat): prihvatljivo za v1.
  Opcionalna nadogradnja: `client_id uuid` kolona na `messages` + unique indeks → ponovni
  pokušaj slanja ne može stvoriti duplikat (mala migracija, preporučeno ali nije blocker).

## 5. Slike u kešu — implementirano 2026-08-05

Blobovi slika se spremaju u IndexedDB (`src/utils/imageCache.js`, odvojena localforage
"polica") pod ključem = storage path. `ChatImage.vue` pri prikazu: (1) pokušaj iz keša →
radi offline; (2) offline bez keša → placeholder (bez visećeg fetcha); (3) online → potpisani
URL za prikaz + keširanje bloba u pozadini za idući put. Keš se briše pri odjavi/brisanju
računa (`clearImageCache` uz `clearAll`). Object URL-ovi se oslobađaju na unmount.

## 6. Redoslijed implementacije (svaka točka samostalno isporučiva)

1. `persistence.js` + localforage (⚠️ odobrenje ovisnosti) — bez potrošača, čisti temelj
2. Pinia plugin + `persist` opcija na 6 storova + brisanje keša u `logout`/`deleteAccount`
   → **ovdje se već dobiva "instant open"**
3. `useNetwork.js` + offline traka + disabled prilozi
4. Outbox u chat storu + optimistične poruke + flush triggeri
5. Pending UI u `MessageList.vue` + retry akcija
6. (Opcionalno) `client_id` migracija — zaštita od duplih poruka pri ponovnom slanju

Procjena: točke 1–2 ≈ dan; 3 ≈ pola dana; 4–5 ≈ 1–2 dana; ukupno ~3–4 dana rada.

## 7. Test checklist

- [ ] Otvori app u airplane modu (nakon prethodnog korištenja) → projekti/poruke/badgevi vidljivi
- [ ] Pošalji 2 poruke offline → obje pending u UI-ju → uključi mrežu → obje stignu, redom, bez duplikata
- [ ] Ubij app s porukama u outboxu → otvori online → poruke se pošalju
- [ ] Odjava → prijava drugim računom → nema tuđeg keša
- [ ] Realtime i dalje radi identično (poslana poruka se pojavi jednom, ne dvaput)
- [ ] Edit/delete/reakcije offline → jasno onemogućeno ili uredna greška, ništa ne "nestane"
- [ ] Web build (mockovi) — sve isto radi u pregledniku

## Povezano

- BACKLOG: pokriva I3 (offline UX) i dio I4; temelj za Razinu 2 (delta sync — traži
  `updated_at` + soft-delete migracije).
- Nakon ovoga, `fetchUnread` scoping fix (već napravljen) + D2 debounce čine offline
  ponašanje badgeva razumnim.
