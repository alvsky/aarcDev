<template>
  <div class="confetti-burst" aria-hidden="true">
    <span v-for="piece in pieces" :key="piece.id" class="confetti-piece" :style="piece.style" />
  </div>
</template>

<script setup>
// Čisti CSS konfeti — bez nove ovisnosti (npr. canvas-confetti). Komadići su
// obični <span>-ovi čija pozicija/boja/trajanje/zanošenje su nasumični, pa
// pad ne izgleda strojno pravilan; animacija je čisto CSS transform (jeftino,
// GPU-ubrzano), nema JS petlje po frameu.
import { computed } from 'vue'

const COLORS = ['#6366F1', '#8B5CF6', '#EC4899', '#EF4444', '#F59E0B', '#10B981', '#3B82F6', '#14B8A6']
const COUNT = 60

const pieces = computed(() =>
  Array.from({ length: COUNT }, (_, i) => {
    const drift = (Math.random() - 0.5) * 240
    const rotate = 360 + Math.random() * 360
    return {
      id: i,
      style: {
        left: `${Math.random() * 100}%`,
        backgroundColor: COLORS[i % COLORS.length],
        animationDelay: `${Math.random() * 0.3}s`,
        animationDuration: `${1.8 + Math.random() * 1.2}s`,
        '--drift': `${drift}px`,
        '--rotate': `${rotate}deg`,
      },
    }
  }),
)
</script>

<style scoped>
.confetti-burst {
  position: fixed;
  inset: 0;
  pointer-events: none;
  z-index: 9999;
  overflow: hidden;
}

.confetti-piece {
  position: absolute;
  top: -10px;
  width: 8px;
  height: 14px;
  opacity: 0.9;
  animation-name: confetti-fall;
  animation-timing-function: linear;
  animation-fill-mode: forwards;
}

@keyframes confetti-fall {
  0% {
    transform: translate(0, 0) rotate(0deg);
    opacity: 1;
  }
  100% {
    transform: translate(var(--drift), 100vh) rotate(var(--rotate));
    opacity: 0;
  }
}
</style>
