import { boot } from 'quasar/wrappers'
import { createI18n } from 'vue-i18n'
import hr from 'src/i18n/hr'
import en from 'src/i18n/en'

export const i18n = createI18n({
  locale: 'en', // ← promijeni 'hr' u 'en'
  fallbackLocale: 'hr',
  messages: { hr, en },
  legacy: false,
})

export default boot(({ app }) => {
  app.use(i18n)
})
