<template>
  <q-dialog v-model="open" persistent>
    <q-card style="min-width: 340px">
      <q-card-section class="row items-center">
        <div class="text-h6">
          {{ project?.id ? $t('projects.edit') : $t('projects.new') }}
        </div>
        <q-space />
        <q-btn flat round dense icon="close" v-close-popup />
      </q-card-section>

      <q-separator />

      <q-card-section class="q-gutter-sm">
        <q-input
          v-model="form.name"
          :label="$t('projects.name')"
          outlined
          dense
          autofocus
          :rules="[(v) => !!v || $t('common.required')]"
        />

        <q-input
          v-model="form.description"
          :label="$t('projects.description')"
          outlined
          dense
          autogrow
          type="textarea"
          rows="3"
        />

        <!-- Odabir boje -->
        <div>
          <div class="text-caption text-grey-6 q-mb-xs">
            {{ $t('projects.color') }}
          </div>
          <div class="row q-gutter-sm">
            <div
              v-for="color in colors"
              :key="color"
              class="color-dot cursor-pointer"
              :style="{ background: color }"
              :class="{ 'color-dot--selected': form.color === color }"
              @click="form.color = color"
            />
          </div>
        </div>

        <!-- Vidljivost — samo pri uređivanju postojećeg (novi je uvijek
             privatan, create_project to nameće) i samo admin/owner smije
             mijenjati (projects_visibility_guard okidač bi to i onako odbio,
             ali ne pokazujemo radnju koja bi svejedno pala). -->
        <div v-if="project?.id && orgsStore.isAdmin">
          <div class="text-caption text-grey-6 q-mb-xs">
            {{ $t('projects.visibilityLabel') }}
          </div>
          <q-btn-toggle
            v-model="form.visibility"
            spread
            no-caps
            toggle-color="primary"
            :options="[
              { label: $t('projects.visibilityOrg'), value: 'org' },
              { label: $t('projects.visibilityPrivate'), value: 'private' },
            ]"
          />
        </div>
      </q-card-section>

      <q-card-actions align="right">
        <q-btn flat :label="$t('common.cancel')" v-close-popup />
        <q-btn color="primary" :label="$t('common.save')" :loading="saving" @click="save" />
      </q-card-actions>
    </q-card>
  </q-dialog>
</template>

<script setup>
import { ref, watch, computed } from 'vue'
import { useProjectsStore } from 'src/stores/projects'
import { useOrgsStore } from 'src/stores/orgs'
import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'

const props = defineProps({
  modelValue: Boolean,
  project: { type: Object, default: null },
})
const emit = defineEmits(['update:modelValue'])

const $q = useQuasar()
const { t } = useI18n()
const projectsStore = useProjectsStore()
const orgsStore = useOrgsStore()
const saving = ref(false)

const colors = [
  '#6366F1',
  '#8B5CF6',
  '#EC4899',
  '#EF4444',
  '#F59E0B',
  '#10B981',
  '#3B82F6',
  '#14B8A6',
]

const open = computed({
  get: () => props.modelValue,
  set: (v) => emit('update:modelValue', v),
})

const form = ref({ name: '', description: '', color: '#6366F1', visibility: 'private' })

watch(
  () => props.modelValue,
  (val) => {
    if (val) {
      form.value = props.project
        ? {
            name: props.project.name,
            description: props.project.description ?? '',
            color: props.project.color ?? '#6366F1',
            visibility: props.project.visibility ?? 'private',
          }
        : { name: '', description: '', color: '#6366F1', visibility: 'private' }
    }
  },
)
async function save() {
  if (!form.value.name.trim()) return
  saving.value = true
  try {
    if (props.project?.id) {
      await projectsStore.updateProject(props.project.id, form.value)
    } else {
      await projectsStore.createProject(form.value)
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
.color-dot {
  width: 28px;
  height: 28px;
  border-radius: 50%;
  border: 2px solid transparent;
  transition: transform 0.15s;
}
.color-dot:hover {
  transform: scale(1.15);
}
.color-dot--selected {
  border-color: #000;
  transform: scale(1.15);
}
</style>
