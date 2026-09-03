// Pretvara URL-ove u tekstu poruke u klikabilne linkove koji se otvaraju u
// vanjskom browseru. Tekst se prvo escape-a (spriječava XSS iz sadržaja
// poruke), tek onda se prepoznati URL-ovi zamjenjuju <a> tagovima — pa je
// v-html izlaz siguran za sadržaj koji su unijeli korisnici.
const URL_RE = /(https?:\/\/[^\s<]+|www\.[^\s<]+)/gi

// Interpunkcija na kraju (npr. "Vidi https://x.com." ili "(https://x.com)")
// ne smije postati dio linka.
const TRAILING_PUNCTUATION_RE = /[.,;:!?)\]}'"]+$/

function escapeHtml(text) {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;')
}

export function useLinkify() {
  function linkifyHtml(text) {
    if (!text) return ''
    const escaped = escapeHtml(text)

    return escaped.replace(URL_RE, (match) => {
      let url = match
      let trailing = ''
      const trailMatch = url.match(TRAILING_PUNCTUATION_RE)
      if (trailMatch) {
        trailing = trailMatch[0]
        url = url.slice(0, -trailing.length)
      }
      if (!url) return match

      const href = url.startsWith('www.') ? `https://${url}` : url
      return `<a href="${href}" target="_blank" rel="noopener noreferrer" class="msg-link">${url}</a>${trailing}`
    })
  }

  return { linkifyHtml }
}
