import { useI18n } from 'vue-i18n'

export function useFormatDate() {
  const { locale } = useI18n()

  function full(ts) {
    return new Date(ts).toLocaleString(locale.value, {
      dateStyle: 'short',
      timeStyle: 'short',
    })
  }

  function smart(ts) {
    const d = new Date(ts)
    const now = new Date()
    // Usporedba datuma koristi lokalnu vremensku zonu, ne UTC
    const dDateStr = d.toLocaleDateString(locale.value)
    const nowDateStr = now.toLocaleDateString(locale.value)
    const isToday = dDateStr === nowDateStr
    if (isToday) {
      return d.toLocaleTimeString(locale.value, { timeStyle: 'short' })
    }
    return d.toLocaleDateString(locale.value, { dateStyle: 'short' })
  }

  function relative(ts) {
    const diff = Math.floor((Date.now() - new Date(ts)) / 1000)
    if (diff < 60) return locale.value === 'hr' ? 'upravo sad' : 'just now'
    if (diff < 3600) {
      const m = Math.floor(diff / 60)
      return locale.value === 'hr' ? `prije ${m} min` : `${m}m ago`
    }
    if (diff < 86400) {
      const h = Math.floor(diff / 3600)
      return locale.value === 'hr' ? `prije ${h} h` : `${h}h ago`
    }
    return full(ts)
  }

  function time(ts) {
    return new Date(ts).toLocaleTimeString(locale.value, {
      timeStyle: 'short',
    })
  }

  return { full, smart, relative, time }
}
