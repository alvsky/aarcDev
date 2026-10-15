import { ref } from 'vue'
import { Capacitor } from '@capacitor/core'

// Zaštita prikaza nestajućih poruka (@capacitor-community/privacy-screen):
// - Android: enable() postavlja FLAG_SECURE — snimka ekrana i video su crni.
// - iOS: snimku ekrana nije moguće spriječiti, ali se snimanje videa ekrana
//   otkriva (screenRecordingStarted/Stopped), pa pozivatelj tada skriva sadržaj.
//   enable() na iOS-u usput sivi aplikaciju u prikazu otvorenih aplikacija.
// Na webu ništa od toga ne postoji — sve su no-op.

// Dijeljeno stanje: događaji stižu samo pri PROMJENI, pa se slušaju od
// pokretanja aplikacije (App.vue), ne tek kad se otvori poruka. Snimanje
// započeto prije pokretanja aplikacije se ne vidi.
const screenRecording = ref(false)
let listening = false

async function plugin() {
  if (!Capacitor.isNativePlatform()) return null
  const { PrivacyScreen } = await import('@capacitor-community/privacy-screen')
  return PrivacyScreen
}

export function usePrivacyScreen() {
  async function watchScreenRecording() {
    if (listening) return
    const p = await plugin()
    if (!p) return
    listening = true
    await p.addListener('screenRecordingStarted', () => (screenRecording.value = true))
    await p.addListener('screenRecordingStopped', () => (screenRecording.value = false))
  }

  async function setProtected(on) {
    const p = await plugin()
    if (!p) return
    try {
      await (on ? p.enable() : p.disable())
    } catch (e) {
      console.error('[privacy-screen]', e)
    }
  }

  return { screenRecording, watchScreenRecording, setProtected }
}
