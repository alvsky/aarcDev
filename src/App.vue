<template>
  <router-view />
</template>

<script setup>
import { onMounted, watch } from 'vue'
import { Capacitor } from '@capacitor/core'
import { useAuthStore } from './stores/auth'
import { useNotificationsStore } from 'src/stores/notifications'
import { useChatStore } from 'src/stores/chat'
import { useBadge } from 'src/composables/useBadge'
import { usePush } from 'src/composables/usePush'
import { useNetwork } from 'src/composables/useNetwork'

const { clearBadge, requestPermission, setBadge } = useBadge()
const { init, registerPendingToken } = usePush()
const { onReconnect } = useNetwork()
const authStore = useAuthStore()
const notifStore = useNotificationsStore()
const chatStore = useChatStore()

// Token koji je stigao prije prijave registriraj čim se korisnik prijavi;
// usput pošalji poruke koje čekaju u outboxu
watch(
  () => authStore.user?.id,
  async (userId) => {
    if (userId) {
      await registerPendingToken()
      await chatStore.flushOutbox()
      await notifStore.fetchUnread()
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
