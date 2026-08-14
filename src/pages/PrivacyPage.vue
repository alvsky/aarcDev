<template>
  <q-layout view="hHh lpR fFf">
    <AppHeader :title="$t('privacy.title')" back />

    <q-page-container>
      <q-page padding class="privacy-page">
        <div class="text-caption privacy-muted q-mb-md">
          {{ $t('privacy.updated', { date: updatedDate }) }}
        </div>

        <p class="privacy-text">{{ $t('privacy.intro') }}</p>

        <div class="text-subtitle2 q-mt-lg q-mb-xs privacy-heading">
          {{ $t('privacy.collectTitle') }}
        </div>
        <p class="privacy-text">{{ $t('privacy.collect') }}</p>

        <div class="text-subtitle2 q-mt-lg q-mb-xs privacy-heading">{{ $t('privacy.useTitle') }}</div>
        <p class="privacy-text">{{ $t('privacy.use') }}</p>

        <div class="text-subtitle2 q-mt-lg q-mb-xs privacy-heading">
          {{ $t('privacy.storageTitle') }}
        </div>
        <p class="privacy-text">{{ $t('privacy.storage') }}</p>

        <div class="text-subtitle2 q-mt-lg q-mb-xs privacy-heading">
          {{ $t('privacy.retentionTitle') }}
        </div>
        <p class="privacy-text">{{ $t('privacy.retention') }}</p>

        <div class="text-subtitle2 q-mt-lg q-mb-xs privacy-heading">
          {{ $t('privacy.contactTitle') }}
        </div>
        <p class="privacy-text">{{ $t('privacy.contact') }}</p>
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup>
import { useI18n } from 'vue-i18n'
import AppHeader from 'src/components/shared/AppHeader.vue'

const { locale } = useI18n()

const updatedDate = new Date('2026-08-14').toLocaleDateString(locale.value, {
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
})
</script>

<style scoped>
.aarc-header {
  background: var(--aarc-header) !important;
}

.privacy-page {
  background: var(--aarc-bg) !important;
}

.privacy-heading {
  color: var(--aarc-text);
}

.privacy-text {
  color: var(--aarc-muted);
  line-height: 1.6;
}

.privacy-muted {
  color: var(--aarc-muted);
}
</style>
