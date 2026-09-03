<template>
  <q-layout view="hHh lpR fFf">
    <AppHeader :title="$t('changelog.title')" back />

    <q-page-container>
      <q-page padding class="changelog-page">
        <div
          v-for="entry in releasesStore.releases"
          :key="entry.build"
          class="changelog-entry q-mb-lg"
        >
          <div class="row items-baseline q-gutter-sm q-mb-xs">
            <div class="text-subtitle1 changelog-heading">
              {{ $t('changelog.version', { version: entry.version, build: entry.build }) }}
            </div>
            <div class="text-caption changelog-muted">{{ formatDate(entry.released_at) }}</div>
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
import { onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import AppHeader from 'src/components/shared/AppHeader.vue'
import { useReleasesStore } from 'src/stores/releases'

const { locale } = useI18n()
const releasesStore = useReleasesStore()

onMounted(() => {
  // Perzistirani keš (ako postoji) crta se odmah; ovo je samo osvježavanje.
  releasesStore.fetchReleases()
})

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
