import { Capacitor } from '@capacitor/core'
import { Notify } from 'quasar'
import { i18n } from 'src/boot/i18n'
import { useNotificationsStore } from 'src/stores/notifications'
import { useAuthStore } from 'src/stores/auth'
import router from 'src/router'

// I2: kind postoji samo na payloadu za NOVE stavke (edge funkcija šalje ga
// na items INSERT), pa je stage uvijek početni — dovoljno da bug/idea/task
// jednoznačno odredi karticu bez dodatnog upita bazi.
const KIND_TAB = { bug: 'bugs', task: 'tbi', idea: 'ideas' }

// Dijeli ga i klik na sistemsku notifikaciju (pushNotificationActionPerformed)
// i klik na in-app banner (pushNotificationReceived, dok je app otvorena) —
// isto odredište, dva različita okidača.
function navigateFromPushData(data) {
  const projectId = data.projectId
  if (!projectId) return

  // I1: tab i meta (item/channel) su sad dio same adrese — ItemListPanel/
  // ChatPage čitaju query kad se mountaju i briše je čim potroše (vidi
  // njihove watchere), da se isti skok ne ponovi kod idućeg običnog ulaska.
  const tab = data.itemId ? (KIND_TAB[data.kind] ?? 'ideas') : 'chat'
  const query = data.itemId ? { item: data.itemId } : { channel: data.channel ?? 'main' }
  router.push({ path: `/project/${projectId}/${tab}`, query })
}

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

      // Android/iOS sam ne prikaže sistemsku notifikaciju dok je app otvorena
      // (to rade samo kad je u pozadini/ugašena) — bez ovoga bi push u
      // foregroundu prošao potpuno nezamijećeno osim tihog rasta brojača.
      const data = notification.data ?? {}
      if (!data.projectId) return
      // Već si unutar tog projekta: bedž/točkice na tabovima to već pokazuju,
      // a ako baš gledaš taj kanal poruka je već stigla uživo (invarijanta 2)
      // — banner bi ovdje bio samo dupli šum.
      if (router.currentRoute.value.params.id === data.projectId) return

      Notify.create({
        message: notification.title ?? '',
        caption: notification.body ?? '',
        position: 'top',
        timeout: 6000,
        color: 'primary',
        icon: 'notifications',
        actions: [
          {
            label: i18n.global.t('notifications.open'),
            color: 'white',
            handler: () => navigateFromPushData(data),
          },
        ],
      })
    })

    PushNotifications.addListener('pushNotificationActionPerformed', (action) => {
      console.log('Push action performed:', action)
      navigateFromPushData(action.notification?.data ?? {})
    })
  }

  return { init, registerPendingToken }
}
