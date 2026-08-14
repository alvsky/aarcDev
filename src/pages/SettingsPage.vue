<template>
  <q-layout view="hHh lpR fFf">
    <AppHeader :title="$t('settings.title')" back />

    <q-page-container>
      <q-page padding class="settings-page">
        <!-- Jezik -->
        <q-card flat bordered class="q-mb-md settings-card">
          <q-card-section>
            <div class="text-subtitle2 q-mb-sm settings-label">{{ $t('settings.language') }}</div>
            <q-btn-toggle
              v-model="lang"
              spread
              :options="langOptions"
              @update:model-value="authStore.setLang"
            />
          </q-card-section>
        </q-card>

        <!-- Tema -->
        <q-card flat bordered class="settings-card">
          <q-card-section>
            <div class="text-subtitle2 q-mb-sm settings-label">{{ $t('settings.darkMode') }}</div>
            <q-toggle
              :model-value="authStore.darkMode"
              :label="authStore.darkMode ? $t('settings.darkMode') : 'Light mode'"
              color="primary"
              @update:model-value="authStore.toggleDarkMode"
            />
          </q-card-section>
        </q-card>
        <!-- Veličina teksta -->
        <q-card flat bordered class="q-mb-md settings-card">
          <q-card-section>
            <div class="text-subtitle2 q-mb-sm settings-label">{{ $t('settings.fontSize') }}</div>
            <q-btn-toggle
              v-model="fontSize"
              spread
              :options="fontSizeOptions"
              @update:model-value="authStore.setFontSize"
            />
          </q-card-section>
        </q-card>

        <!-- O aplikaciji / privatnost -->
        <q-card flat bordered class="settings-card">
          <q-list separator>
            <q-item clickable v-ripple @click="$router.push('/about')">
              <q-item-section>{{ $t('settings.about') }}</q-item-section>
              <q-item-section side>
                <q-icon name="chevron_right" color="grey" />
              </q-item-section>
            </q-item>
            <q-item clickable v-ripple @click="$router.push('/privacy')">
              <q-item-section>{{ $t('settings.privacy') }}</q-item-section>
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
import { ref, onMounted, computed } from 'vue'
import AppHeader from 'src/components/shared/AppHeader.vue'
import { useAuthStore } from 'src/stores/auth'
import { useI18n } from 'vue-i18n'
const { t } = useI18n()

const authStore = useAuthStore()
const lang = ref(authStore.lang)

const fontSize = ref(authStore.fontSize)

const fontSizeOptions = computed(() => [
  { label: t('settings.fontSizes.small'), value: 'small' },
  { label: t('settings.fontSizes.medium'), value: 'medium' },
  { label: t('settings.fontSizes.large'), value: 'large' },
  { label: t('settings.fontSizes.xlarge'), value: 'xlarge' },
])

const langOptions = [
  { label: 'Hrvatski', value: 'hr' },
  { label: 'English', value: 'en' },
]

onMounted(() => {
  lang.value = authStore.lang
})
</script>

<style scoped>
.aarc-header {
  background: var(--aarc-header) !important;
}

.settings-page {
  background: var(--aarc-bg) !important;
}

.settings-card {
  background: var(--aarc-surface) !important;
  border-color: var(--aarc-border) !important;
  border-radius: 16px !important;
}

.settings-label {
  color: var(--aarc-text);
}
</style>
