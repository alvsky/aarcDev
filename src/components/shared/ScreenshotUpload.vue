<template>
  <div>
    <div class="text-caption text-grey-6 q-mb-xs">
      {{ $t('bugs.screenshot') }}
      <span v-if="max" class="q-ml-xs">({{ totalCount }}/{{ max }})</span>
    </div>

    <!-- Već otpremljeni screenshotovi (samo pri uređivanju) -->
    <div v-if="existing.length" class="row q-gutter-sm q-mb-sm">
      <div v-for="shot in existing" :key="shot.id" class="screenshot-thumb">
        <ChatImage :path="shot.url" :alt="shot.name || $t('chat.imageAlt')" />
        <q-btn
          flat
          round
          dense
          size="sm"
          icon="close"
          class="screenshot-thumb-remove"
          @click="$emit('remove-existing', shot)"
        />
      </div>
    </div>

    <!-- Tek odabrane, još neotpremljene slike -->
    <div v-if="modelValue.length" class="row q-gutter-sm q-mb-sm">
      <div v-for="(file, i) in modelValue" :key="i" class="screenshot-thumb">
        <img :src="previews[i]" :alt="file.name" class="screenshot-thumb-img" />
        <q-btn
          flat
          round
          dense
          size="sm"
          icon="close"
          class="screenshot-thumb-remove"
          @click="removePending(i)"
        />
      </div>
    </div>

    <div v-if="totalCount < max" class="row q-gutter-sm">
      <q-btn
        outline
        color="primary"
        icon="attach_file"
        :label="$t('bugs.addScreenshot')"
        size="sm"
        @click="triggerFilePicker"
      />
      <q-btn
        outline
        color="primary"
        icon="content_paste"
        :label="$t('bugs.pasteScreenshot')"
        size="sm"
        @click="pasteFromClipboard"
      />
    </div>
    <div v-else class="text-caption text-grey-5">
      {{ $t('bugs.screenshotMax', { max }) }}
    </div>

    <input
      ref="fileInput"
      type="file"
      accept="image/*"
      multiple
      class="hidden"
      @change="onFileSelected"
    />

    <div v-if="!isNative && totalCount < max" class="text-caption text-grey-5 q-mt-xs">
      {{ $t('chat.pasteHint') }}
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch } from 'vue'
import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'
import { Capacitor } from '@capacitor/core'
import ChatImage from 'src/components/chat/ChatImage.vue'

const props = defineProps({
  modelValue: { type: Array, default: () => [] }, // File[], tek odabrano — ne otpremljeno
  existing: { type: Array, default: () => [] }, // već otpremljeno (uređivanje), {id,url,name}
  max: { type: Number, default: 5 },
})
const emit = defineEmits(['update:modelValue', 'remove-existing'])

const $q = useQuasar()
const { t } = useI18n()
const fileInput = ref(null)
const previews = ref([])
const isNative = Capacitor.isNativePlatform()

const totalCount = computed(() => props.existing.length + props.modelValue.length)

// Svaki File dobiva svoj objectURL za preview; čiste se čim ih zamijeni novi
// popis (i pri unmountu, defineExpose nije potreban jer watcher pokriva sve).
watch(
  () => props.modelValue,
  (files, prevFiles) => {
    for (const url of previews.value) URL.revokeObjectURL(url)
    previews.value = files.map((f) => URL.createObjectURL(f))
    void prevFiles
  },
  { immediate: true },
)

function triggerFilePicker() {
  fileInput.value?.click()
}

function remainingSlots() {
  return Math.max(0, props.max - totalCount.value)
}

function addFiles(files) {
  const room = remainingSlots()
  if (room <= 0) return
  const images = files.filter((f) => f?.type.startsWith('image/')).slice(0, room)
  if (!images.length) return
  emit('update:modelValue', [...props.modelValue, ...images])
}

function onFileSelected(e) {
  addFiles(Array.from(e.target.files ?? []))
  if (fileInput.value) fileInput.value.value = ''
}

async function pasteFromClipboard() {
  if (remainingSlots() <= 0) return
  try {
    const clipboardItems = await navigator.clipboard.read()
    for (const item of clipboardItems) {
      const imageType = item.types.find((type) => type.startsWith('image/'))
      if (imageType) {
        const blob = await item.getType(imageType)
        addFiles([new File([blob], 'screenshot.png', { type: imageType })])
        return
      }
    }
    $q.notify({ type: 'warning', message: t('chat.imageAlt') })
  } catch {
    $q.notify({ type: 'warning', message: t('chat.pasteHint') })
  }
}

function removePending(index) {
  emit(
    'update:modelValue',
    props.modelValue.filter((_, i) => i !== index),
  )
}
</script>

<style scoped>
.hidden {
  display: none;
}

.screenshot-thumb {
  position: relative;
  width: 80px;
  height: 80px;
}

/* !important nadjačava ChatImage.vue's vlastiti scoped .chat-img
   (max-width/max-height:auto) — poredak dvaju scoped <style> blokova u
   izlazu nije zajamčen, pa se na selector-specifičnost ne može osloniti. */
.screenshot-thumb :deep(img),
.screenshot-thumb-img {
  width: 80px !important;
  height: 80px !important;
  max-width: 80px !important;
  max-height: 80px !important;
  border-radius: 8px;
  border: 1px solid rgba(0, 0, 0, 0.12);
  object-fit: cover !important;
}

.screenshot-thumb-remove {
  position: absolute;
  top: -8px;
  right: -8px;
  background: rgba(0, 0, 0, 0.6);
  color: white;
}
</style>
