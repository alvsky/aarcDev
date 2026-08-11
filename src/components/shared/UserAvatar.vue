<template>
  <!-- size/font-size kao calc() vezan na --aarc-font-scale: kad korisnik promijeni
       veličinu teksta u postavkama, avatar (kutija i inicijali) skalira zajedno s
       ostatkom sučelja bez da komponenta išta sama preračunava. -->
  <q-avatar :size="boxSize" color="primary" text-color="white">
    <img v-if="imgSrc" :src="imgSrc" :alt="fullName" />
    <template v-else>{{ initials }}</template>
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
/* object-fit nije Quasarov zadani stil za img unutar q-avatar — bez ovoga bi
   se pravokutna slika razvukla da popuni krug umjesto da se izreže. Sve
   ostalo (veličina, centriranje, font-size inicijala) prepušteno je čistom
   Quasarovom zadanom ponašanju, bez naših dodatnih pravila. */
img {
  object-fit: cover;
}
</style>
