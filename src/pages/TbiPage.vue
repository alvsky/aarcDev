<template>
  <!-- Ploča: sve u aktivnom radu, bez obzira je li krenulo kao ideja, bug ili
       zadatak — zato se ovdje prikazuje i vrsta stavke. -->
  <ItemListPanel
    :project-id="projectId"
    :items="itemsStore.tbi(projectId)"
    kind="task"
    group="tbi"
    show-kind
    :new-label="$t('tbi.new')"
    :empty-text="$t('tbi.noItems')"
  />
</template>

<script setup>
import { onMounted } from 'vue'
import { useItemsStore } from 'src/stores/items'
import ItemListPanel from 'src/components/shared/ItemListPanel.vue'

const props = defineProps({ projectId: String })
const itemsStore = useItemsStore()

onMounted(async () => {
  await itemsStore.fetchItems(props.projectId)
})
</script>
