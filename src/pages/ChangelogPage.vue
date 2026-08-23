<template>
  <q-layout view="hHh lpR fFf">
    <AppHeader :title="$t('changelog.title')" back />

    <q-page-container>
      <q-page padding class="changelog-page">
        <div
          v-for="entry in entries"
          :key="entry.build"
          class="changelog-entry q-mb-lg"
        >
          <div class="row items-baseline q-gutter-sm q-mb-xs">
            <div class="text-subtitle1 changelog-heading">
              {{ $t('changelog.version', { version: entry.version, build: entry.build }) }}
            </div>
            <div class="text-caption changelog-muted">{{ formatDate(entry.date) }}</div>
          </div>
          <div class="text-body2 changelog-summary q-mb-sm">{{ entry.summary }}</div>
          <ul class="changelog-list">
            <li v-for="(item, i) in entry.items" :key="i" class="text-body2">{{ item }}</li>
          </ul>
        </div>
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup>
import { useI18n } from 'vue-i18n'
import AppHeader from 'src/components/shared/AppHeader.vue'

const { locale } = useI18n()

// Zrcali CHANGELOG.md (izvor istine za tekst) — samo unosi vidljivi korisniku,
// namjerno hrvatski kao i sam CHANGELOG.md; puni prijevod povijesti izlazi iz
// opsega ovog zadatka. Ručno se dodaje novi unos uz svaki novi build (vidi
// CLAUDE.md — Quick facts, versioning).
const entries = [
  {
    version: '1.0',
    build: 30,
    date: '2026-08-23',
    summary: 'Popis promjena, sad i u samoj aplikaciji.',
    items: [
      'Nova stranica "Popis promjena", dostupna iz Postavki → O aplikaciji — pregled svih dosadašnjih izdanja bez potrebe za GitHubom.',
    ],
  },
  {
    version: '1.0',
    build: 28,
    date: '2026-08-23',
    summary: 'Poruke koje nestaju nakon čitanja, i chat prilagođen desktopu.',
    items: [
      'Nova opcija u chatu: poruka koja nestaje nakon čitanja. Uključi se gumbom s ikonom vatre pored polja za unos poruke; ostalim članovima se prikaže kao skriven mjehurić dok ga ne otvore, a sadržaj se u tom trenutku nepovratno briše (uključno s privitkom). Kad je pročitaju svi članovi projekta, u chatu ostaje samo trag "Otvoreno" — vidljiv svima, kao kod WhatsAppa.',
      'Chat thread (otvoren iz ideje/buga/zadatka) sad ima istu ograničenu širinu kao ostatak aplikacije na tabletu/desktopu — dosad se razvlačio preko cijelog ekrana.',
    ],
  },
  {
    version: '1.0',
    build: 27,
    date: '2026-08-15',
    summary: 'Registracija konačno radi, pozivnice se šalju e-mailom.',
    items: [
      'Popravljena registracija/prijava koja je vraćala grešku 500 — Resend SMTP pošiljatelj je koristio testnu (sandbox) adresu koja je smjela slati samo vlasniku Resend računa, pa nitko drugi nije mogao dovršiti registraciju. Sad koristi pravu, verificiranu domenu.',
      'Neuspjela prijava/registracija/reset lozinke sad prikazuje razumljivu poruku umjesto sirove (ponekad prazne, vidljive kao gole vitičaste zagrade) greške sa servera.',
      'Pozivnice u organizaciju sad stižu i e-mailom (uz link koji se i dalje kopira u međuspremnik) — prije se link morao ručno proslijediti.',
      'Nova web stranica za prihvat pozivnice (za nekoga tko još nema instaliranu app) — prijava/registracija i pridruživanje organizaciji izravno u pregledniku.',
      'Uklonjena "Ctrl+V za lijepljenje" uputa na mobilnim uređajima (nema smisla bez tipkovnice); na webu sad piše i za Mac (Cmd+V).',
    ],
  },
  {
    version: '1.0',
    build: 26,
    date: '2026-08-14',
    summary: 'Android app ikona, dostupnija navigacija i nove stranice.',
    items: [
      'Android app ikona zamijenjena pravim aarc logom (dosad je bio zadani Capacitorov placeholder).',
      'Podnožje s navigacijom (Home / Organizacija / Profil) sad je vidljivo i na stranicama Organizacije i Profila, ne samo na Homeu.',
      'Nove stranice "O aplikaciji" (verzija, build broj) i "Pravila privatnosti", dostupne iz Postavki.',
    ],
  },
  {
    version: '1.0',
    build: 25,
    date: '2026-08-13',
    summary: 'Android push notifikacije i popravci dodira na notifikaciju.',
    items: [
      'Android push notifikacije sad rade (dosad nikad nisu, nedostajala je konfiguracija).',
      'Dodir na notifikaciju za komentar unutar ideje/buga/zadatka sad otvara baš taj thread umjesto uvijek Rasprave.',
      'Dodir na notifikaciju dok je app u pozadini (ne ugašena) sad ispravno otvara cilj, umjesto da ostane na trenutnom zaslonu.',
      'Dodir na notifikaciju za drugi projekt sad stvarno prebaci na taj projekt, umjesto da samo promijeni karticu unutar starog.',
      'Notifikacija se sad pojavljuje i dok gledaš app (prije se pojavljivala samo kad je app u pozadini ili ugašena) — kratki banner s gumbom "Otvori", osim kad si već unutar tog istog projekta.',
      'U poruku se sad može upisati novi red (Enter na mobitelu više ne šalje poruku odmah).',
    ],
  },
  {
    version: '1.0',
    build: 24,
    date: '2026-08-12',
    summary: 'Dotjerivanje razmaka nakon prvog testiranja na uređaju.',
    items: [
      'Pod-tabovi u chatu (Rasprava / Offtopic) zauzimaju upola manje visine — taj prostor sad ide popisu poruka.',
      'Manje praznog prostora pri dnu početnog zaslona.',
      'Donja navigacija više nema upadljivu praznu traku ispod natpisa.',
      'Popis ideja/bugova/zadataka: alatna traka s filtrima ostaje na mjestu dok se popis skrola (prije se moralo skrolati skroz na vrh da bi se promijenio filtar), a suvišan naslov iznad nje je maknut — kartica u zaglavlju već kaže gdje si.',
      'Prijelomi redaka u opisima i koracima za reprodukciju se čuvaju pri prikazu.',
    ],
  },
  {
    version: '1.0',
    build: 23,
    date: '2026-08-12',
    summary: 'Prva zabilježena verzija. Obuhvaća sve dosad napravljeno, ne samo zadnji krug.',
    items: [
      'Organizacije s ulogama (vlasnik, admin, član, gost), pozivnice, statistika po članu.',
      'Projekti: vidljivost, prikvačeni projekti, pretraga, praćenje odvojeno od pristupa.',
      'Ideje, bugovi i TBI kao jedna stavka koja mijenja fazu — prihvaćanje ništa ne duplicira.',
      'Jedan chat po stavci — kanali, odgovori, reakcije, slike, push notifikacije, brojevi nepročitanog.',
      'Registracija, reset lozinke, avatar, offline rad, tamna tema, hrvatski/engleski.',
    ],
  },
]

function formatDate(iso) {
  return new Date(iso).toLocaleDateString(locale.value, {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  })
}
</script>

<style scoped>
.changelog-page {
  background: var(--aarc-bg) !important;
}

.changelog-heading {
  color: var(--aarc-text);
}

.changelog-muted {
  color: var(--aarc-muted);
}

.changelog-summary {
  color: var(--aarc-text);
  font-weight: 500;
}

.changelog-list {
  margin: 0;
  padding-left: 20px;
  color: var(--aarc-muted);
  line-height: 1.5;
}

.changelog-list li {
  margin-bottom: 4px;
}

.changelog-entry:not(:last-child) {
  border-bottom: 1px solid var(--aarc-border);
  padding-bottom: 16px;
}
</style>
