import localforage from 'localforage'

// Keš slika (blobovi) za offline prikaz — ključ je storage path slike.
// Odvojena "polica" od state keša (persistence.js) jer drži binarne podatke.
const store = localforage.createInstance({
  name: 'aarc',
  storeName: 'images',
})

export async function getCachedImageUrl(path) {
  try {
    const blob = await store.getItem(path)
    if (blob) return URL.createObjectURL(blob)
  } catch (e) {
    console.warn('image cache read error:', e)
  }
  return null
}

export async function cacheImage(path, blob) {
  try {
    await store.setItem(path, blob)
  } catch (e) {
    console.warn('image cache write error:', e)
  }
}

export async function removeCachedImage(path) {
  if (!path) return
  try {
    await store.removeItem(path)
  } catch (e) {
    console.warn('image cache remove error:', e)
  }
}

export async function clearImageCache() {
  try {
    await store.clear()
  } catch (e) {
    console.warn('image cache clear error:', e)
  }
}
