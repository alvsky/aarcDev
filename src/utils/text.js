// Skida dijakritičke znakove (č/ć/š/ž/đ i sl.) da pretraga radi neovisno o
// tome piše li korisnik "velicina" ili "veličina" — bez ovoga substring
// match promašuje čim se ijedna strana razlikuje u naglascima.
const DIACRITICS = new RegExp(
  '[' + String.fromCharCode(0x0300) + '-' + String.fromCharCode(0x036f) + ']',
  'g',
)

export function normalizeSearch(text) {
  return (text ?? '')
    .normalize('NFD')
    .replace(DIACRITICS, '')
    .toLowerCase()
}
