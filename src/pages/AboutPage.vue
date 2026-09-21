<template>
  <q-layout view="hHh lpR fFf">
    <AppHeader :title="$t('about.title')" back />

    <q-page-container>
      <q-page padding class="about-page">
        <div class="column items-center q-pt-lg q-pb-xl">
          <img src="/logos/aarc_t_225-75.png" alt="aarc" class="about-logo" />
          <div class="text-caption about-muted q-mt-md text-center">{{ $t('about.tagline') }}</div>
        </div>

        <q-card flat bordered class="about-card">
          <q-card-section class="row items-center">
            <div class="col about-label">{{ $t('about.version') }}</div>
            <div class="about-value">{{ releasesStore.latest?.version ?? '—' }}</div>
          </q-card-section>
          <q-separator />
          <q-card-section class="row items-center" @click="onBuildTap">
            <div class="col about-label">{{ $t('about.build') }}</div>
            <div class="about-value">{{ releasesStore.latest?.build ?? '—' }}</div>
          </q-card-section>
          <q-separator />
          <q-list>
            <q-item clickable v-ripple @click="$router.push('/changelog')">
              <q-item-section>{{ $t('about.changelogLink') }}</q-item-section>
              <q-item-section side>
                <q-icon name="chevron_right" color="grey" />
              </q-item-section>
            </q-item>
            <q-separator />
            <q-item clickable v-ripple @click="$router.push('/privacy')">
              <q-item-section>{{ $t('about.privacyLink') }}</q-item-section>
              <q-item-section side>
                <q-icon name="chevron_right" color="grey" />
              </q-item-section>
            </q-item>
          </q-list>
        </q-card>

        <PolaroidReveal v-if="showPolaroid" @close="showPolaroid = false" />
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import AppHeader from 'src/components/shared/AppHeader.vue'
import PolaroidReveal from 'src/components/shared/PolaroidReveal.vue'
import { useReleasesStore } from 'src/stores/releases'

const releasesStore = useReleasesStore()

onMounted(() => {
  // Ne await-a se — releasesStore.latest je perzistiran (keš iz prošle
  // sesije), pa stranica ima što prikazati odmah; ovo je samo osvježavanje.
  releasesStore.fetchReleases()
})

// Easter egg — 5 tapova na redak s brojem builda u roku od 2s (isti obrazac
// kao logo u AppHeader.vue).
const showPolaroid = ref(false)
let buildTapCount = 0
let buildTapTimer = null

function onBuildTap() {
  buildTapCount++
  clearTimeout(buildTapTimer)
  buildTapTimer = setTimeout(() => {
    buildTapCount = 0
  }, 2000)
  if (buildTapCount >= 5) {
    buildTapCount = 0
    showPolaroid.value = true
  }
}

onUnmounted(() => clearTimeout(buildTapTimer))
</script>

<style scoped>
.aarc-header {
  background: var(--aarc-header) !important;
}

.about-page {
  background: var(--aarc-bg) !important;
}

.about-logo {
  width: 180px;
  height: auto;
}

.about-muted {
  color: var(--aarc-muted);
  max-width: 320px;
}

.about-card {
  background: var(--aarc-surface) !important;
  border-color: var(--aarc-border) !important;
  border-radius: 16px !important;
}

.about-label {
  color: var(--aarc-text);
}

.about-value {
  color: var(--aarc-muted);
}
</style>
