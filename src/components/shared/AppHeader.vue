<template>
  <q-header class="app-header">
    <q-toolbar class="app-toolbar q-px-md">
      <!-- Lijevo: custom slot (npr. avatar) ili back gumb -->
      <slot name="left">
        <q-btn v-if="back" flat round dense icon="arrow_back" color="white" @click="onBack" />
      </slot>

      <img src="/logos/aarc_t_225-75.png" alt="aarc" class="app-logo" @click="onLogoClick" />

      <ConfettiBurst v-if="showConfetti" />

      <q-toolbar-title v-if="title || $slots.title" class="text-white">
        <slot name="title">{{ title }}</slot>
      </q-toolbar-title>
      <q-space v-else />

      <!-- Offline indikator -->
      <q-icon v-if="!online" name="cloud_off" color="red" size="22px" class="q-mr-sm">
        <q-tooltip>{{ $t('common.offline') }}</q-tooltip>
      </q-icon>

      <!-- Dodatne akcije prije settings gumba -->
      <slot name="actions" />

      <q-btn
        v-if="settings"
        flat
        round
        dense
        icon="settings"
        color="white"
        @click="$router.push('/settings')"
      />
    </q-toolbar>

    <!-- Tabovi (npr. ProjectPage) -->
    <div class="app-tabs-wrap">
      <slot name="tabs" />
    </div>
  </q-header>
</template>

<script setup>
import { ref, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'
import { useNetwork } from 'src/composables/useNetwork'
import ConfettiBurst from './ConfettiBurst.vue'

const props = defineProps({
  title: { type: String, default: '' },
  back: { type: Boolean, default: false },
  backTo: { type: String, default: '' },
  settings: { type: Boolean, default: false },
})

const router = useRouter()
const $q = useQuasar()
const { t } = useI18n()
const { online } = useNetwork()

function onBack() {
  if (props.backTo) router.push(props.backTo)
  else router.back()
}

// Easter egg — logo je u zaglavlju koje koristi svaki ekran (AppHeader je
// dijeljena komponenta), pa je ovo jedino mjesto potrebno za cijelu app.
// 10 tapova u roku od 2s; klik i dalje normalno vodi na Home, brojanje je
// samo dodatak.
const showConfetti = ref(false)
let logoTapCount = 0
let logoTapTimer = null

function onLogoClick() {
  router.push('/')
  logoTapCount++
  clearTimeout(logoTapTimer)
  logoTapTimer = setTimeout(() => {
    logoTapCount = 0
  }, 2000)
  if (logoTapCount >= 10) {
    logoTapCount = 0
    celebrate()
  }
}

function celebrate() {
  showConfetti.value = true
  $q.notify({ message: t('common.easterEgg'), icon: 'celebration', color: 'primary', timeout: 3000 })
  // Malo dulje od najduže moguće animacije pojedinog komada konfetija
  // (1.8s + 1.2s trajanje + 0.3s kašnjenje, vidi ConfettiBurst.vue) da nijedan
  // komad ne nestane rezanjem prije nego stigne skroz pasti.
  setTimeout(() => {
    showConfetti.value = false
  }, 3500)
}

onUnmounted(() => clearTimeout(logoTapTimer))
</script>

<style scoped>
.app-header {
  background: var(--aarc-header) !important;
  /* Sadržaj počinje ispod notcha/status bara; pozadina se proteže do vrha */
  /* padding-top: env(safe-area-inset-top); */
  border-bottom: 1px solid rgba(0, 209, 255, 0.1);
}

/* I10: traka (pozadina) ostaje puna širina, sadržaj unutra poravnat s
   ograničenom širinom stranice ispod (--aarc-content-max) na tabletu/desktopu. */
.app-toolbar,
.app-tabs-wrap {
  max-width: var(--aarc-content-max);
  margin-inline: auto;
}

.app-logo {
  height: 22px;
  width: auto;
  cursor: pointer;
  margin: 0 8px;
}
</style>
