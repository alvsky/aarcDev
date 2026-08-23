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
            <div class="about-value">{{ appVersion }}</div>
          </q-card-section>
          <q-separator />
          <q-card-section class="row items-center">
            <div class="col about-label">{{ $t('about.build') }}</div>
            <div class="about-value">{{ appBuild }}</div>
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
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup>
import AppHeader from 'src/components/shared/AppHeader.vue'

// Prati iOS/Android/CHANGELOG.md — bump ručno zajedno s njima (vidi CLAUDE.md).
const appVersion = '1.0'
const appBuild = '30'
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
