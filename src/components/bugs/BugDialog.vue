<template>
  <q-dialog v-model="open" persistent>
    <q-card style="min-width: 340px; width: 90vw; max-width: 500px">
      <q-card-section class="row items-center">
        <div class="text-h6">
          {{ bug?.id ? $t('common.edit') : $t('bugs.new') }}
        </div>
        <q-space />
        <q-btn flat round dense icon="close" v-close-popup />
      </q-card-section>

      <q-separator />

      <q-card-section class="q-gutter-sm">
        <q-input
          v-model="form.title"
          :label="$t('common.title')"
          outlined
          dense
          autofocus
          :rules="[(v) => !!v || $t('common.required')]"
        />

        <q-field :label="$t('common.description')" outlined stack-label style="min-height: 160px">
          <template #control>
            <textarea
              v-model="form.description"
              class="q-field__native full-width"
              style="
                min-height: 140px;
                resize: vertical;
                padding: 8px 0;
                line-height: 1.5;
                font-size: 14px;
                font-family: inherit;
                border: none;
                outline: none;
                background: transparent;
              "
              :placeholder="$t('common.description')"
              @paste="onDescriptionPaste"
            />
          </template>
        </q-field>

        <!-- Screenshot upload -->
        <ScreenshotUpload v-model="pendingImage" />

        <q-select
          v-model="form.priority"
          :label="$t('common.priority')"
          outlined
          dense
          :options="priorityOptions"
          emit-value
          map-options
        />

        <q-select
          v-if="bug?.id"
          v-model="form.status"
          :label="$t('common.status')"
          outlined
          dense
          :options="statusOptions"
          emit-value
          map-options
        />
      </q-card-section>

      <q-card-actions align="right">
        <q-btn flat :label="$t('common.cancel')" v-close-popup />
        <q-btn color="negative" :label="$t('common.save')" :loading="saving" @click="save" />
      </q-card-actions>
    </q-card>
  </q-dialog>
</template>

<script setup>
import { ref, watch, computed } from 'vue'
import { useBugsStore } from 'src/stores/bugs'
import { useImageUpload } from 'src/composables/useImageUpload'
import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'

const props = defineProps({
  modelValue: Boolean,
  bug: { type: Object, default: null },
  projectId: { type: String, required: true },
})
const emit = defineEmits(['update:modelValue'])

const $q = useQuasar()
const { t } = useI18n()
const bugsStore = useBugsStore()
const { uploadImage } = useImageUpload()

const saving = ref(false)
const pendingImage = ref(null)

const open = computed({
  get: () => props.modelValue,
  set: (v) => emit('update:modelValue', v),
})

const form = ref({
  title: '',
  description: '',
  priority: 'med',
  status: 'open',
})

watch(
  () => props.modelValue,
  (val) => {
    if (val) {
      form.value = props.bug
        ? {
            title: props.bug.title,
            description: props.bug.description ?? '',
            priority: props.bug.priority,
            status: props.bug.status,
          }
        : { title: '', description: '', priority: 'med', status: 'open' }
      if (!props.bug) pendingImage.value = null
    }
  },
)

const priorityOptions = computed(() => [
  { label: t('bugs.priority.low'), value: 'low' },
  { label: t('bugs.priority.med'), value: 'med' },
  { label: t('bugs.priority.high'), value: 'high' },
])

const statusOptions = computed(() => [
  { label: t('bugs.status.open'), value: 'open' },
  { label: t('bugs.status.in_progress'), value: 'in_progress' },
  { label: t('bugs.status.testing'), value: 'testing' },
  { label: t('bugs.status.closed'), value: 'closed' },
])

async function save() {
  if (!form.value.title.trim()) return
  saving.value = true
  try {
    let screenshotUrl = null
    let screenshotType = null
    let screenshotName = null

    if (pendingImage.value) {
      const uploaded = await uploadImage(pendingImage.value, { maxWidth: 1280, quality: 0.6 })
      screenshotUrl = uploaded.path
      screenshotType = uploaded.type
      screenshotName = uploaded.name
    }

    if (props.bug?.id) {
      await bugsStore.updateBug(props.bug.id, {
        ...form.value,
        screenshot_url: screenshotUrl ?? props.bug.screenshot_url,
        screenshot_type: screenshotType ?? props.bug.screenshot_type,
        screenshot_name: screenshotName ?? props.bug.screenshot_name,
      })
    } else {
      await bugsStore.createBug({
        projectId: props.projectId,
        title: form.value.title,
        description: form.value.description,
        priority: form.value.priority,
        screenshotUrl,
        screenshotType,
        screenshotName,
      })
    }
    open.value = false
    $q.notify({ type: 'positive', message: t('settings.saved') })
  } catch (e) {
    $q.notify({ type: 'negative', message: e.message })
  } finally {
    saving.value = false
  }
}
</script>

<style scoped>
.hidden {
  display: none;
}
</style>
