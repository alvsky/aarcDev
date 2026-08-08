import { Capacitor } from '@capacitor/core'

let Badge = null

// VAŽNO: Capacitor plugin je Proxy — ne smije se vraćati iz async funkcije niti awaitati
// direktno (pristup na .then postaje native poziv "then" koji ne postoji, interni promise
// pukne i vanjski await visi zauvijek). Zato ensureBadge() ne vraća plugin, nego samo
// puni modul-scope varijablu.
async function ensureBadge() {
  if (Badge) return
  try {
    const mod = await import('@capawesome/capacitor-badge')
    Badge = mod.Badge
  } catch {
    Badge = {
      set: async () => {},
      clear: async () => {},
      checkPermissions: async () => ({ display: 'denied' }),
      requestPermissions: async () => ({ display: 'denied' }),
    }
  }
}

export function useBadge() {
  const isNative = Capacitor.isNativePlatform()

  async function setBadge(count) {
    if (!isNative) return
    try {
      await ensureBadge()
      await Badge.set({ count })
    } catch {
      console.warn('Badge set error')
    }
  }

  async function clearBadge() {
    if (!isNative) return
    try {
      await ensureBadge()
      await Badge.clear()
    } catch {
      console.warn('Badge clear error')
    }
  }

  async function requestPermission() {
    if (!isNative) return true
    try {
      await ensureBadge()
      const { display } = await Badge.checkPermissions()
      if (display === 'granted') return true
      const { display: result } = await Badge.requestPermissions()
      return result === 'granted'
    } catch {
      return false
    }
  }

  return { setBadge, clearBadge, requestPermission }
}
