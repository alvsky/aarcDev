import { Capacitor } from '@capacitor/core'

// Modul-scope singleton (isti obrazac kao useNetwork.js) — jedan native
// listener, dijeljen niz callbackova. Odvojeno od App.vue-ove vlastite
// appStateChange logike (badge/outbox) jer stranice koje se montiraju/
// demontiraju (ProjectPage, ChatPage) trebaju svoju pretplatu s urednim
// unsubscribeom, što App.vue ne treba (živi cijeli lifetime appa).
const resumeCallbacks = []
let initialized = false

function notifyResume() {
  for (const cb of resumeCallbacks) {
    try {
      cb()
    } catch (e) {
      console.warn('onResume callback error:', e)
    }
  }
}

async function ensureInit() {
  if (initialized || !Capacitor.isNativePlatform()) return
  initialized = true
  const { App: CapApp } = await import('@capacitor/app')
  CapApp.addListener('appStateChange', ({ isActive }) => {
    if (isActive) notifyResume()
  })
}

export function useAppResume() {
  ensureInit()

  // Vraća unsubscribe funkciju — pozovi u onUnmounted.
  function onResume(cb) {
    resumeCallbacks.push(cb)
    return () => {
      const idx = resumeCallbacks.indexOf(cb)
      if (idx !== -1) resumeCallbacks.splice(idx, 1)
    }
  }

  return { onResume }
}
