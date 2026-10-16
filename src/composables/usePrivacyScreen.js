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
const screenshotHandlers = new Set()
let listening = false

// ⚠️ Capacitor dodatak (Proxy) se NE SMIJE vratiti iz async funkcije niti njime
// razriješiti Promise: Proxy na svako svojstvo, pa i `then`, vraća funkciju, pa
// ga JS tretira kao Promise i zove nepostojeću nativnu metodu `then` — await
// tada nikad ne završi, bez greške i bez loga (2026-10-16: zbog toga nije radio
// ni FLAG_SECURE ni prijava snimke). Zato se drži u varijabli, a async
// funkcija vraća samo true/false.
let PrivacyScreen = null

async function loadPlugin() {
  if (!Capacitor.isNativePlatform()) return false
  if (!PrivacyScreen) {
    const mod = await import('@capacitor-community/privacy-screen')
    PrivacyScreen = mod.PrivacyScreen
  }
  return true
}

export function usePrivacyScreen() {
  // Nikad ne baca — poziva se pri pokretanju aplikacije i ne smije srušiti
  // ništa što dolazi iza (vidi App.vue).
  async function watchScreenRecording() {
    if (listening) return
    listening = true
    try {
      if (!(await loadPlugin())) return
      await PrivacyScreen.addListener(
        'screenRecordingStarted',
        () => (screenRecording.value = true),
      )
      await PrivacyScreen.addListener(
        'screenRecordingStopped',
        () => (screenRecording.value = false),
      )
      // iOS: snimka je već napravljena kad ovo stigne — može se samo prijaviti.
      await PrivacyScreen.addListener('screenshotTaken', () => {
        console.log('[privacy-screen] screenshotTaken')
        screenshotHandlers.forEach((fn) => fn())
      })
      console.log('[privacy-screen] listeners registered')
    } catch (e) {
      listening = false
      console.error('[privacy-screen] addListener failed:', e)
    }
  }

  // Vraća funkciju za odjavu.
  function onScreenshotTaken(fn) {
    screenshotHandlers.add(fn)
    return () => screenshotHandlers.delete(fn)
  }

  async function setProtected(on) {
    try {
      if (!(await loadPlugin())) return
      await (on ? PrivacyScreen.enable() : PrivacyScreen.disable())
    } catch (e) {
      console.error('[privacy-screen]', e)
    }
  }

  return { screenRecording, watchScreenRecording, setProtected, onScreenshotTaken }
}
