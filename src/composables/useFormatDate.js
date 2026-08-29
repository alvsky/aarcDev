export function useFormatDate() {
  // TODO: kasnije dodati u postavke korisnika, za sada forsiran hrvatski
  function pad(n) {
    return String(n).padStart(2, '0')
  }

  function formatDate(ts) {
    const d = new Date(ts)
    return `${pad(d.getDate())}.${pad(d.getMonth() + 1)}.${d.getFullYear()}.`
  }

  function formatTime(ts) {
    const d = new Date(ts)
    return `${pad(d.getHours())}:${pad(d.getMinutes())}`
  }

  function full(ts) {
    return `${formatDate(ts)}, ${formatTime(ts)}`
  }

  function smart(ts) {
    const d = new Date(ts)
    const now = new Date()
    // Usporedba datuma koristi lokalnu vremensku zonu, ne UTC
    const isToday =
      d.getDate() === now.getDate() &&
      d.getMonth() === now.getMonth() &&
      d.getFullYear() === now.getFullYear()
    if (isToday) {
      return formatTime(ts)
    }
    return formatDate(ts)
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
    return formatTime(ts)
  }

  return { full, smart, relative, time }
}
