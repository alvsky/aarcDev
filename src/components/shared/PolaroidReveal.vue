<template>
  <div class="polaroid-overlay" @click="$emit('close')">
    <!-- Bljesak fotoaparata točno na vrhuncu okreta (kad je kartica "na rubu",
         nevidljiva) — pojačava dojam da se upravo nešto snimilo. -->
    <div class="polaroid-flash" :class="{ 'polaroid-flash-active': flashing }" />

    <div class="polaroid-stage">
      <div class="polaroid-flip" :class="{ 'polaroid-flip-revealed': revealed }">
        <!-- Prednja strana: fotka koju očekuješ -->
        <div class="polaroid-card polaroid-front">
          <div class="polaroid-photo" :class="{ 'polaroid-developed': developed }">
            <img :src="nicePhoto" alt="" />
          </div>
          <div class="polaroid-caption">{{ $t('about.easterEggCaption') }}</div>
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

defineEmits(['close'])

const developed = ref(false)
const revealed = ref(false)
const flashing = ref(false)
const timers = []

// Pauza prije okreta — koliko lijepa slika ostaje na ekranu prije zamjene.
const REVEAL_DELAY = 3000

onMounted(() => {
  // 1) "Razvijanje" prednje fotke — malo kašnjenje da se overlay stigne pojaviti prije animacije
  timers.push(setTimeout(() => (developed.value = true), 80))
  // 2) Pauza da se lijepa slika stigne prepoznati, pa okret
  timers.push(setTimeout(() => (revealed.value = true), REVEAL_DELAY))
  // 3) Bljesak točno na vrhuncu okreta (flip traje 0.6s, pola puta = kartica je "na rubu")
  timers.push(setTimeout(() => (flashing.value = true), REVEAL_DELAY + 300))
  timers.push(setTimeout(() => (flashing.value = false), REVEAL_DELAY + 460))
})

onUnmounted(() => timers.forEach(clearTimeout))
</script>

<style scoped>
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

.polaroid-flip {
  position: relative;
  width: 100%;
  /* .polaroid-back je position:absolute; inset:0 — bez eksplicitnog position
     ovdje bi se pozicionirao prema .polaroid-stage umjesto prema visini koju
     određuje .polaroid-front (jedini element u tijeku dokumenta). */
  transform-style: preserve-3d;
  transition: transform 0.6s cubic-bezier(0.4, 0.1, 0.2, 1);
  transform: rotateY(0deg);
}

.polaroid-flip-revealed {
  transform: rotateY(180deg);
}

.polaroid-card {
  backface-visibility: hidden;
  background: #fff;
  padding: 14px 14px 20px;
  border-radius: 2px;
  box-shadow: 0 12px 30px rgba(0, 0, 0, 0.5);
}

.polaroid-front {
  position: relative;
  transform: rotate(-3deg);
}

.polaroid-back {
  position: absolute;
  inset: 0;
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
  /* Kurziv umjesto rukopisnog fonta — "Segoe Script"/"Brush Script MT" su
     jedva čitljivi na malom zaslonu, ovo zadržava topao, ležeran dojam bez
     mučenja oka. Sistemski font stack, bez novog web-fonta. */
  font-style: italic;
  font-weight: 500;
  font-size: 15px;
  line-height: 1.35;
  color: #333;
}
</style>
