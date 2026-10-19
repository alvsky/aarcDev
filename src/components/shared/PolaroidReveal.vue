<template>
  <div class="polaroid-overlay" @click="$emit('close')">
    <!-- Bljesak fotoaparata točno na vrhuncu okreta (kad je kartica "na rubu",
         nevidljiva) — pojačava dojam da se upravo nešto snimilo. -->
    <div class="polaroid-flash" :class="{ 'polaroid-flash-active': flashing }" />

    <div class="polaroid-stage" :class="{ 'polaroid-landscape': showSillier }">
      <div
        class="polaroid-flip"
        :class="{
          'polaroid-flip-revealed': stage === 1,
          'polaroid-flip-sillier': stage === 2,
        }"
      >
        <!-- Prednja strana: fotka koju očekuješ — a u trećem koraku, dok je
             okrenuta od gledatelja, potiho postaje sillier fotka. -->
        <div class="polaroid-card polaroid-front">
          <div class="polaroid-photo" :class="{ 'polaroid-developed': developed }">
            <img :src="showSillier ? sillierPhoto : nicePhoto" alt="" />
          </div>
          <div class="polaroid-caption">
            {{ showSillier ? $t('about.easterEggCaptionSillier') : $t('about.easterEggCaption') }}
          </div>
        </div>

        <!-- Stražnja strana: ono što stvarno dobiješ -->
        <div class="polaroid-card polaroid-back">
          <div class="polaroid-photo polaroid-developed">
            <img :src="sillyPhoto" alt="" />
          </div>
          <div class="polaroid-caption">{{ $t('about.easterEggCaptionSilly') }}</div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
// Redoslijed: razvije se "lijepa" slika (prednja strana), kratka pauza da
// oko stigne prepoznati je, pa se cijela kartica okrene (3D flip) i otkrije
// "blesavu" sliku na poleđini — ista fora kao okretanje prave polaroid
// fotke da pokažeš prijatelju drugu koju si skrivao iza nje.
import { ref, onMounted, onUnmounted } from 'vue'
import nicePhoto from 'src/assets/easter-egg/nice.jpg'
import sillyPhoto from 'src/assets/easter-egg/silly.jpg'

// Treća, "sillier" fotka (src/assets/easter-egg/sillier.jpg|jpeg|png) — glob umjesto
// importa da build ne pukne dok datoteke još nema; bez nje nema trećeg koraka.
const sillierModules = import.meta.glob('../../assets/easter-egg/sillier.{jpg,jpeg,png}', {
  eager: true,
  import: 'default',
})
const sillierPhoto = Object.values(sillierModules)[0] ?? null

defineEmits(['close'])

const developed = ref(false)
// 0 = lijepa (prednja), 1 = blesava (stražnja), 2 = sillier (opet prednja)
const stage = ref(0)
const showSillier = ref(false)
const flashing = ref(false)
const timers = []

// Pauza prije okreta — koliko svaka slika ostaje na ekranu prije sljedeće.
const REVEAL_DELAY = 3000
const FLIP_MS = 600

function flash(at) {
  timers.push(setTimeout(() => (flashing.value = true), at + FLIP_MS / 2))
  timers.push(setTimeout(() => (flashing.value = false), at + FLIP_MS / 2 + 160))
}

onMounted(() => {
  // 1) "Razvijanje" prednje fotke — malo kašnjenje da se overlay stigne pojaviti prije animacije
  timers.push(setTimeout(() => (developed.value = true), 80))
  // 2) Pauza da se lijepa slika stigne prepoznati, pa okret na blesavu,
  //    s bljeskom točno na vrhuncu okreta (kartica je tada "na rubu")
  timers.push(setTimeout(() => (stage.value = 1), REVEAL_DELAY))
  flash(REVEAL_DELAY)
  if (!sillierPhoto) return
  // 3) Nakon iste pauze okret dalje u ISTOM smjeru (180° → 360°). Fotka se
  //    mijenja točno na pola okreta, kad je kartica bokom i nevidljiva — tada
  //    i okvir prelazi u položeni (sillier je landscape), pa se skok u
  //    veličini ne vidi (a pokriva ga i bljesak).
  timers.push(setTimeout(() => (stage.value = 2), REVEAL_DELAY * 2))
  timers.push(setTimeout(() => (showSillier.value = true), REVEAL_DELAY * 2 + FLIP_MS / 2))
  flash(REVEAL_DELAY * 2)
})

onUnmounted(() => timers.forEach(clearTimeout))
</script>

<style scoped>
/* Patrick Hand (SIL OFL) — samostalno pohranjen (bez CDN-a, ostaje offline-first
   kao i ostatak appa) umjesto sistemskog kurziva; "tiskani freehand" izgled,
   čitljivo i na malom zaslonu. Dvije podskupine (latin + latin-ext) jer latin
   sam ne pokriva č/ć/š/ž/đ — isti obrazac kojim ih Google Fonts sam poslužuje. */
@font-face {
  font-family: 'Patrick Hand';
  font-style: normal;
  font-weight: 400;
  font-display: swap;
  src: url('../../assets/fonts/patrick-hand-latin.woff2') format('woff2');
  unicode-range:
    U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+2000-206F, U+20AC,
    U+2122, U+2191, U+2193, U+2212, U+2215;
}

@font-face {
  font-family: 'Patrick Hand';
  font-style: normal;
  font-weight: 400;
  font-display: swap;
  src: url('../../assets/fonts/patrick-hand-latin-ext.woff2') format('woff2');
  unicode-range:
    U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+1E00-1E9F, U+2020, U+2113,
    U+2C60-2C7F, U+A720-A7FF;
}

.polaroid-overlay {
  position: fixed;
  inset: 0;
  z-index: 9999;
  background: rgba(0, 0, 0, 0.75);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  animation: polaroid-backdrop-in 0.25s ease;
}

@keyframes polaroid-backdrop-in {
  from {
    opacity: 0;
  }
  to {
    opacity: 1;
  }
}

.polaroid-flash {
  position: fixed;
  inset: 0;
  background: white;
  opacity: 0;
  pointer-events: none;
}

.polaroid-flash-active {
  opacity: 0.85;
  transition: opacity 0.08s ease-out;
}

.polaroid-stage {
  perspective: 1200px;
  width: 260px;
}

.polaroid-stage.polaroid-landscape {
  width: min(380px, 90vw);
}

.polaroid-landscape .polaroid-photo {
  aspect-ratio: 3 / 2;
}

.polaroid-flip {
  /* Obje strane u istoj ćeliji grida: kartica je visoka koliko VIŠA strana.
     Dok je stražnja bila position:absolute; inset:0, preuzimala je visinu
     prednje, pa joj je natpis u dva reda (silly) ispadao ispod kartice. */
  display: grid;
  width: 100%;
  transform-style: preserve-3d;
  transition: transform 0.6s cubic-bezier(0.4, 0.1, 0.2, 1);
  transform: rotateY(0deg);
}

.polaroid-flip-revealed {
  transform: rotateY(180deg);
}

.polaroid-flip-sillier {
  transform: rotateY(360deg);
}

.polaroid-card {
  grid-area: 1 / 1;
  backface-visibility: hidden;
  background: #fff;
  padding: 14px 14px 20px;
  border-radius: 2px;
  box-shadow: 0 12px 30px rgba(0, 0, 0, 0.5);
}

.polaroid-front {
  transform: rotate(-3deg);
}

.polaroid-back {
  transform: rotate(-3deg) rotateY(180deg);
}

.polaroid-photo {
  width: 100%;
  aspect-ratio: 506 / 900;
  overflow: hidden;
  background: #ddd;
  filter: blur(14px) saturate(0.4) brightness(0.85);
  opacity: 0;
  transition:
    filter 1s ease-out,
    opacity 0.4s ease-out;
}

.polaroid-photo img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

.polaroid-developed {
  filter: blur(0) saturate(1) brightness(1);
  opacity: 1;
}

.polaroid-caption {
  margin-top: 12px;
  text-align: center;
  font-family: 'Patrick Hand', sans-serif;
  font-size: 20px;
  line-height: 1.35;
  color: #333;
}
</style>
