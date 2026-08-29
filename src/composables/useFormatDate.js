export function useFormatDate() {
  // TODO: kasnije dodati u postavke korisnika, za sada forsiran hrvatski
  const LOCALE = 'hr-HR'

  function full(ts) {
    return new Date(ts).toLocaleString(LOCALE, {
      dateStyle: 'short',
      timeStyle: 'short',
    })
  }

  function smart(ts) {
    const d = new Date(ts)
    const now = new Date()
    // Usporedba datuma koristi lokalnu vremensku zonu, ne UTC
    const dDateStr = d.toLocaleDateString(LOCALE)
    const nowDateStr = now.toLocaleDateString(LOCALE)
    const isToday = dDateStr === nowDateStr
    if (isToday) {
      return d.toLocaleTimeString(LOCALE, { timeStyle: 'short' })
    }
    return d.toLocaleDateString(LOCALE, { dateStyle: 'short' })
  }

  function relative(ts) {
    const diff = Math.floor((Date.now() - new Date(ts)) / 1000)
    if (diff < 60) return 'upravo sad'
    if (diff < 3600) {
      const m = Math.floor(diff / 60)
      return `prije ${m} min`
    }
    if (diff < 86400) {
      const h = Math.floor(diff / 3600)
      return `prije ${h} h`
    }
    return full(ts)
  }

  function time(ts) {
    return new Date(ts).toLocaleTimeString(LOCALE, {
      timeStyle: 'short',
    })
  }

  return { full, smart, relative, time }
}
