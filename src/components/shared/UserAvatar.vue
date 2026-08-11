<template>
  <!-- size/font-size kao calc() vezan na --aarc-font-scale: kad korisnik promijeni
       veličinu teksta u postavkama, avatar (kutija i inicijali) skalira zajedno s
       ostatkom sučelja bez da komponenta išta sama preračunava. -->
  <q-avatar :size="boxSize" :font-size="glyphSize" color="primary" text-color="white">
    <img v-if="imgSrc" :src="imgSrc" :alt="fullName" />
    <span v-else class="avatar-initials">{{ initials }}</span>
  </q-avatar>
</template>

<script setup>
import { ref, computed, watch, onUnmounted } from 'vue'
import { useImageUpload } from 'src/composables/useImageUpload'
import { isOnline } from 'src/composables/useNetwork'
import { getCachedImageUrl, cacheImage } from 'src/utils/imageCache'

const props = defineProps({
  // Storage path (profiles.avatar_url), ne URL — isti obrazac kao ChatImage.
  avatarUrl: { type: String, default: null },
  fullName: { type: String, default: '' },
  size: { type: Number, default: 40 },
})

const { getSignedUrl } = useImageUpload()
const imgSrc = ref(null)
let objectUrl = null

const boxSize = computed(() => `calc(${props.size}px * var(--aarc-font-scale, 1))`)
const glyphSize = computed(
  () => `calc(${Math.round(props.size * 0.38)}px * var(--aarc-font-scale, 1))`,
)

const initials = computed(
  () =>
    props.fullName
      ?.split(' ')
      .map((w) => w[0])
      .join('')
      .toUpperCase()
      .slice(0, 2) || '?',
)

async function load(path) {
  if (objectUrl) {
    URL.revokeObjectURL(objectUrl)
    objectUrl = null
  }
  imgSrc.value = null
  if (!path) return

  const cached = await getCachedImageUrl(path)
  if (cached) {
    objectUrl = cached
    imgSrc.value = cached
    return
  }

  if (!isOnline()) return

  const url = await getSignedUrl(path, 'avatars')
  imgSrc.value = url
  if (url) {
    fetch(url)
      .then((r) => r.blob())
      .then((blob) => cacheImage(path, blob))
      .catch(() => {})
  }
}

watch(() => props.avatarUrl, load, { immediate: true })

onUnmounted(() => {
  if (objectUrl) URL.revokeObjectURL(objectUrl)
})
</script>

<style scoped>
/* Quasar već postavlja width/height: inherit i border-radius: inherit na avatar img;
   object-fit nije njegov pa ga dodajemo da slika ne izobliči krug. */
img {
  object-fit: cover;
}

/* q-avatar__content je oko inicijala postavljen kao flex red; bez ovoga je "V" bio
   sam raw tekstualni čvor u tom redu — sad je u vlastitom bloku pa se centrira
   pouzdano bez obzira na susjedne (praznotekstne) čvorove koje Vue ostavi u DOM-u. */
.avatar-initials {
  display: block;
  text-align: center;
}
</style>
