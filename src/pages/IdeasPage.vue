<template>
  <!-- Lijevak: ideje koje još čekaju odluku. Prihvaćene odlaze na TBI ploču. -->
  <ItemListPanel
    :project-id="projectId"
    :items="itemsStore.ideas(projectId)"
    kind="idea"
    group="ideas"
    :new-label="$t('ideas.new')"
    :empty-text="$t('ideas.noIdeas')"
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
