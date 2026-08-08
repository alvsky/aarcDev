<template>
  <div>
    <div class="text-caption text-grey-6 q-mb-xs">{{ $t('bugs.screenshot') }}</div>

    <div v-if="modelValue" class="row items-center q-gutter-sm q-mb-sm">
      <img
        :src="preview"
        style="
          height: 80px;
          width: auto;
          border-radius: 8px;
          border: 1px solid rgba(0, 0, 0, 0.12);
          object-fit: cover;
        "
        :alt="$t('chat.imageAlt')"
      />
      <div class="col text-caption text-grey-6 ellipsis">{{ modelValue.name }}</div>
      <q-btn flat round dense icon="close" size="sm" @click="clear" />
    </div>

    <div class="row q-gutter-sm">
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

    <input ref="fileInput" type="file" accept="image/*" class="hidden" @change="onFileSelected" />

    <div class="text-caption text-grey-5 q-mt-xs">
      {{ $t('chat.pasteHint') }}
    </div>
  </div>
</template>

<script setup>
import { ref, watch } from 'vue'
import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'

const props = defineProps({
  modelValue: { type: File, default: null },
})
const emit = defineEmits(['update:modelValue'])

const $q = useQuasar()
const { t } = useI18n()
const fileInput = ref(null)
const preview = ref(null)

watch(
  () => props.modelValue,
  (file) => {
    console.log('ScreenshotUpload modelValue changed:', file?.name)
    if (!file) {
      if (preview.value) URL.revokeObjectURL(preview.value)
      preview.value = null
    } else {
      // Postavi preview kad file dođe izvana
      preview.value = URL.createObjectURL(file)
    }
  },
)
function triggerFilePicker() {
  fileInput.value?.click()
}

function onFileSelected(e) {
  setPending(e.target.files[0])
}

async function pasteFromClipboard() {
  try {
    const clipboardItems = await navigator.clipboard.read()
    for (const item of clipboardItems) {
      const imageType = item.types.find((type) => type.startsWith('image/'))
      if (imageType) {
        const blob = await item.getType(imageType)
        setPending(new File([blob], 'screenshot.png', { type: imageType }))
        return
      }
    }
    $q.notify({ type: 'warning', message: 'Nema slike u clipboardu' })
  } catch {
    $q.notify({ type: 'warning', message: t('chat.pasteHint') })
  }
}

function setPending(file) {
  if (!file?.type.startsWith('image/')) return
  if (preview.value) URL.revokeObjectURL(preview.value)
  preview.value = URL.createObjectURL(file)
  emit('update:modelValue', file)
}

function clear() {
  if (preview.value) URL.revokeObjectURL(preview.value)
  preview.value = null
  emit('update:modelValue', null)
  if (fileInput.value) fileInput.value.value = ''
}
</script>

<style scoped>
.hidden {
  display: none;
}
</style>
