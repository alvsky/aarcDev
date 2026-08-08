import { useI18n } from 'vue-i18n'

export function useFormatDate() {
  const { locale } = useI18n()

  function full(ts) {
    return new Date(ts).toLocaleString(locale.value, {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    })
  }

  function smart(ts) {
    const d = new Date(ts)
    const now = new Date()
    const isToday = d.toDateString() === now.toDateString()
    if (isToday) {
      return d.toLocaleTimeString(locale.value, { hour: '2-digit', minute: '2-digit' })
    }
    return d.toLocaleDateString(locale.value, { day: '2-digit', month: '2-digit' })
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
      hour: '2-digit',
      minute: '2-digit',
    })
  }

  return { full, smart, relative, time }
}
