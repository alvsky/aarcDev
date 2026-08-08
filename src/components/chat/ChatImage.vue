<template>
  <div>
    <q-skeleton v-if="loading" type="rect" width="220px" height="140px" />

    <img v-else-if="imgSrc" :src="imgSrc" :alt="alt" class="chat-img" @click="lightbox = true" />

    <div v-else class="text-caption text-grey-5">[slika nedostupna]</div>

    <!-- Lightbox -->
    <q-dialog v-model="lightbox" maximized>
      <div class="lightbox-wrap flex flex-center cursor-pointer" @click="lightbox = false">
        <img :src="imgSrc" :alt="alt" class="lightbox-img" />
        <q-btn
          flat
          round
          dense
          icon="close"
          color="white"
          class="lightbox-close"
          @click.stop="lightbox = false"
        />
      </div>
    </q-dialog>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { useImageUpload } from 'src/composables/useImageUpload'
import { isOnline } from 'src/composables/useNetwork'
import { getCachedImageUrl, cacheImage } from 'src/utils/imageCache'

const props = defineProps({
  path: { type: String, required: true },
  alt: { type: String, default: 'Screenshot' },
})

const { getSignedUrl } = useImageUpload()
const imgSrc = ref(null)
const loading = ref(true)
const lightbox = ref(false)
let objectUrl = null // object URL iz keša — treba ga osloboditi na unmount

onMounted(async () => {
  try {
    // 1) Lokalni keš — radi i offline
    const cached = await getCachedImageUrl(props.path)
    if (cached) {
      objectUrl = cached
      imgSrc.value = cached
      return
    }

    // 2) Offline i nema keša → placeholder (bez visećeg fetcha)
    if (!isOnline()) return

    // 3) Online → potpisani URL za prikaz + keširaj blob u pozadini za idući put
    const url = await getSignedUrl(props.path)
    imgSrc.value = url
    if (url) {
      fetch(url)
        .then((r) => r.blob())
        .then((blob) => cacheImage(props.path, blob))
        .catch(() => {})
    }
  } catch {
    // slika nedostupna
  } finally {
    loading.value = false
  }
})

onUnmounted(() => {
  if (objectUrl) URL.revokeObjectURL(objectUrl)
})
</script>

<style scoped>
.chat-img {
  max-width: 280px;
  max-height: 200px;
  width: auto;
  height: auto;
  border-radius: 8px;
  object-fit: contain;
  cursor: zoom-in;
  border: 1px solid rgba(0, 0, 0, 0.08);
  display: block;
}

.lightbox-wrap {
  background: rgba(0, 0, 0, 0.85);
  width: 100%;
  height: 100%;
  position: relative;
}

.lightbox-img {
  max-width: 95vw;
  max-height: 90vh;
  object-fit: contain;
  border-radius: 4px;
}

.lightbox-close {
  position: absolute;
  top: 16px;
  right: 16px;
}
</style>
