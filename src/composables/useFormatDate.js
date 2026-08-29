export function useFormatDate() {
  // TODO: kasnije dodati u postavke korisnika, za sada forsiran hrvatski
  const LOCALE = 'hr-HR'

  function full(ts) {
    return new Date(ts).toLocaleString(LOCALE, {
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
    // Usporedba datuma koristi lokalnu vremensku zonu, ne UTC
    const dDateStr = d.toLocaleDateString(LOCALE, { day: '2-digit', month: '2-digit', year: 'numeric' })
    const nowDateStr = now.toLocaleDateString(LOCALE, { day: '2-digit', month: '2-digit', year: 'numeric' })
    const isToday = dDateStr === nowDateStr
    if (isToday) {
      return d.toLocaleTimeString(LOCALE, { hour: '2-digit', minute: '2-digit' })
    }
    return d.toLocaleDateString(LOCALE, { day: '2-digit', month: '2-digit' })
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
      hour: '2-digit',
      minute: '2-digit',
    })
  }

  return { full, smart, relative, time }
}
