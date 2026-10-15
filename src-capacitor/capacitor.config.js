const { defineCapacitorConfig } = require('@quasar/app-vite/capacitor')

module.exports = defineCapacitorConfig({
  appId: 'com.vitka.collabapp',
  appName: 'aarcDev',
  plugins: {
    // Zaštita se pali samo dok je otvorena nestajuća poruka (usePrivacyScreen),
    // ne od pokretanja. preventScreenshots: false gasi iOS trik koji pri
    // pokretanju premjesti cijeli prozor aplikacije u "sigurno" tekstualno
    // polje — krhko i djeluje na cijelu aplikaciju. Android FLAG_SECURE na to
    // ne ovisi.
    PrivacyScreen: {
      enable: false,
      preventScreenshots: false,
    },
  },
})
