<template>
  <q-header class="app-header">
    <q-toolbar class="app-toolbar q-px-md">
      <!-- Lijevo: custom slot (npr. avatar) ili back gumb -->
      <slot name="left">
        <q-btn v-if="back" flat round dense icon="arrow_back" color="white" @click="onBack" />
      </slot>

      <img src="/logos/aarc_t_225-75.png" alt="aarc" class="app-logo" @click="$router.push('/')" />

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
    <slot name="tabs" />
  </q-header>
</template>

<script setup>
import { useRouter } from 'vue-router'
import { useNetwork } from 'src/composables/useNetwork'

const props = defineProps({
  title: { type: String, default: '' },
  back: { type: Boolean, default: false },
  backTo: { type: String, default: '' },
  settings: { type: Boolean, default: false },
})

const router = useRouter()
const { online } = useNetwork()

function onBack() {
  if (props.backTo) router.push(props.backTo)
  else router.back()
}
</script>

<style scoped>
.app-header {
  background: var(--aarc-header) !important;
  /* Sadržaj počinje ispod notcha/status bara; pozadina se proteže do vrha */
  /* padding-top: env(safe-area-inset-top); */
  border-bottom: 1px solid rgba(0, 209, 255, 0.1);
}

.app-logo {
  height: 22px;
  width: auto;
  cursor: pointer;
  margin: 0 8px;
}
</style>
