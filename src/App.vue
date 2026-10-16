<template>
  <router-view />
</template>

<script setup>
import { onMounted, watch } from 'vue'
import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'
import { Capacitor } from '@capacitor/core'
import { useAuthStore } from './stores/auth'
import { useNotificationsStore } from 'src/stores/notifications'
import { useChatStore } from 'src/stores/chat'
import { useFeatureFlagsStore } from 'src/stores/featureFlags'
import { useBadge } from 'src/composables/useBadge'
import { usePush } from 'src/composables/usePush'
import { useNetwork } from 'src/composables/useNetwork'
import { usePrivacyScreen } from 'src/composables/usePrivacyScreen'

const { clearBadge, requestPermission, setBadge } = useBadge()
const { init, registerPendingToken } = usePush()
const { onReconnect } = useNetwork()
const { watchScreenRecording } = usePrivacyScreen()
const authStore = useAuthStore()
const notifStore = useNotificationsStore()
const chatStore = useChatStore()
const featureFlagsStore = useFeatureFlagsStore()
const $q = useQuasar()
const { t } = useI18n()

// Netko je snimio zaslon moje nestajuće poruke — obavijest dok je app otvoren
// (push stiže i kad nije, preko push-on-message).
let stopScreenshotReports = null

// Token koji je stigao prije prijave registriraj čim se korisnik prijavi;
// usput pošalji poruke koje čekaju u outboxu
watch(
  () => authStore.user?.id,
  async (userId) => {
    stopScreenshotReports?.()
    stopScreenshotReports = null
    if (userId) {
      stopScreenshotReports = chatStore.subscribeScreenshotReports(userId, ({ takerName }) =>
        $q.notify({
          icon: 'photo_camera',
          message: t('chat.screenshotReported', { name: takerName }),
          timeout: 5000,
        }),
      )
      await registerPendingToken()
      await chatStore.flushOutbox()
      await notifStore.fetchUnread()
      await featureFlagsStore.fetchFlags()
    }
  },
)

// Povratak mreže: pošalji poruke iz outboxa i osvježi unread
onReconnect(async () => {
  if (authStore.user) {
    await chatStore.flushOutbox()
    await notifStore.fetchUnread()
  }
})

onMounted(async () => {
  await authStore.init()
  await clearBadge()
  await requestPermission()
  await init()
  // Namjerno NAKON push init() i bez await: kad je stajalo ispred, greška
  // dodatka na iOS-u prekinula je cijeli onMounted — push init se nije
  // izvršio pa klik na obavijest više nije otvarao thread (2026-10-16).
  watchScreenRecording()

  if (Capacitor.isNativePlatform()) {
    const { App: CapApp } = await import('@capacitor/app')
    CapApp.addListener('appStateChange', async ({ isActive }) => {
      if (isActive) {
        await clearBadge()
        if (authStore.user) {
          await chatStore.flushOutbox()
          await notifStore.fetchUnread()
          const total = Object.values(notifStore.unread).reduce((sum, p) => sum + (p.total ?? 0), 0)
          if (total > 0) {
            await setBadge(total)
          }
        }
      }
    })
  }
})
</script>
