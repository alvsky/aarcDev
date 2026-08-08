import { ref } from 'vue'
import { Capacitor } from '@capacitor/core'

// Modul-scope singleton (kao pending token u usePush) — svi potrošači dijele isto stanje
const online = ref(typeof navigator !== 'undefined' ? navigator.onLine : true)
const reconnectCallbacks = []
let initialized = false

function notifyReconnect() {
  for (const cb of reconnectCallbacks) {
    try {
      cb()
    } catch (e) {
      console.warn('onReconnect callback error:', e)
    }
  }
}

async function initNative() {
  // VAŽNO: Capacitor plugin je Proxy — ne smije se vraćati iz async funkcije niti
  // awaitati direktno (isto pravilo kao u useBadge.js). Zato se ovdje samo poziva,
  // nikad ne vraća modul namespace van ove funkcije.
  const { Network } = await import('@capacitor/network')

  const status = await Network.getStatus()
  online.value = status.connected

  await Network.addListener('networkStatusChange', (status) => {
    const wasOffline = !online.value
    online.value = status.connected
    if (wasOffline && status.connected) notifyReconnect()
  })
}

function initWeb() {
  window.addEventListener('online', () => {
    online.value = true
    notifyReconnect()
  })
  window.addEventListener('offline', () => {
    online.value = false
  })
}

function ensureInit() {
  if (initialized || typeof window === 'undefined') return
  initialized = true

  if (Capacitor.isNativePlatform()) {
    initNative().catch((e) => console.warn('Network plugin init error:', e))
  } else {
    initWeb()
  }
}

// Pouzdano stanje mreže za storove (na iOS-u je navigator.onLine nepouzdan u WebViewu,
// pa treba čitati isti izvor kao UI — Capacitor Network plugin preko ovog singletona).
export function isOnline() {
  ensureInit()
  return online.value
}

export function useNetwork() {
  ensureInit()

  function onReconnect(cb) {
    reconnectCallbacks.push(cb)
  }

  return { online, onReconnect }
}
