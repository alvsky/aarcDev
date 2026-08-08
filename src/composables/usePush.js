import { Capacitor } from '@capacitor/core'
import { useNotificationsStore } from 'src/stores/notifications'
import { useAuthStore } from 'src/stores/auth'

// Token može stići prije prijave (init se pokreće na startu aplikacije) —
// tada ga čuvamo ovdje i registriramo tek kad se korisnik prijavi.
let pendingToken = null
let pendingPlatform = null

async function registerOrQueue(token, platform) {
  const auth = useAuthStore()
  const notifStore = useNotificationsStore()

  if (auth.user) {
    await notifStore.registerPushToken(token, platform)
    pendingToken = null
    pendingPlatform = null
  } else {
    pendingToken = token
    pendingPlatform = platform
  }
}

export function usePush() {
  const isNative = Capacitor.isNativePlatform()

  async function registerPendingToken() {
    if (pendingToken) {
      await registerOrQueue(pendingToken, pendingPlatform)
    }
  }

  async function init() {
    if (!isNative) return

    const platform = Capacitor.getPlatform()

    const { PushNotifications } = await import('@capacitor/push-notifications')

    const current = await PushNotifications.checkPermissions()
    console.log('Push perm BEFORE request:', JSON.stringify(current))

    const perm = await PushNotifications.requestPermissions()
    console.log('Push perm AFTER request:', JSON.stringify(perm))
    if (perm.receive !== 'granted') {
      console.warn('Push permission not granted')
      return
    }

    if (platform === 'ios') {
      let attempts = 0
      const interval = setInterval(async () => {
        attempts++
        const token = localStorage.getItem('fcmToken')
        console.log(`Attempt ${attempts}, localStorage token:`, token ? token.slice(0, 20) : 'none')

        if (token && token.length > 100) {
          clearInterval(interval)
          localStorage.removeItem('fcmToken')
          console.log('Registering token:', token.slice(0, 20))
          await registerOrQueue(token, platform)
        }

        if (attempts >= 30) {
          clearInterval(interval)
          console.warn('FCM token timeout')
        }
      }, 1000)
    }

    await PushNotifications.register()

    PushNotifications.addListener('registration', async ({ value: token }) => {
      console.log('Capacitor registration token:', token.slice(0, 20))
      console.log('Token length:', token.length)

      if (platform === 'android') {
        await registerOrQueue(token, platform)
      }
    })

    PushNotifications.addListener('registrationError', (err) => {
      console.error('Push registration error:', err)
    })

    PushNotifications.addListener('pushNotificationReceived', async (notification) => {
      console.log('Push received foreground:', notification)
      // Dok je app u foregroundu, iOS ne primjenjuje aps.badge na ikonu sam —
      // moramo eksplicitno osvježiti i postaviti badge kroz naš izvor istine
      const notifStore = useNotificationsStore()
      const auth = useAuthStore()
      if (auth.user) {
        await notifStore.fetchUnread()
      }
    })

    PushNotifications.addListener('pushNotificationActionPerformed', (action) => {
      console.log('Push action performed:', action)
    })
  }

  return { init, registerPendingToken }
}
