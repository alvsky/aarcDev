<template>
  <!-- Thread chat preko cijelog ekrana. Uski dijalog uz rub bio je izvor prelijevanja
       i vodoravnog skrolanja, pa thread sad koristi isti raspored kao glavni chat. -->
  <q-dialog
    v-model="open"
    maximized
    transition-show="slide-up"
    transition-hide="slide-down"
    @hide="onHide"
  >
    <q-card class="column no-wrap thread-card">
      <div class="thread-header row items-center no-wrap q-px-sm col-auto">
        <q-btn flat round dense icon="arrow_back" color="white" @click="open = false" />
        <div class="col q-ml-sm text-subtitle2 text-white ellipsis">{{ title }}</div>
      </div>

      <q-separator />

      <ChatPanel ref="panelRef" class="col" :project-id="projectId" :item-id="itemId" />
    </q-card>
  </q-dialog>
</template>

<script setup>
import { ref, computed } from 'vue'
import ChatPanel from './ChatPanel.vue'

const props = defineProps({
  modelValue: { type: Boolean, required: true },
  title: { type: String, default: '' },
  projectId: { type: String, required: true },
  itemId: { type: String, default: null },
})

const emit = defineEmits(['update:modelValue', 'close'])

const panelRef = ref(null)

const open = computed({
  get: () => props.modelValue,
  set: (v) => emit('update:modelValue', v),
})

function onHide() {
  // Odgovor pripada threadu iz kojeg je pokrenut i ne smije preživjeti zatvaranje.
  panelRef.value?.clearReply()
  emit('close')
}
</script>

<style scoped>
.thread-card {
  height: 100%;
  background: var(--aarc-surface);
}

.thread-header {
  background: var(--aarc-header);
  /* Maksimirani dijalog ide ispod statusne trake, pa header nosi safe-area sam. */
  padding-top: max(env(safe-area-inset-top), 8px);
  padding-bottom: 8px;
}
</style>
