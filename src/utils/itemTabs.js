// Koja kartica (ideas/bugs/tbi) je matični pogled za ovu stavku, po
// kind/stage — vidi docs/item-model.md. Izdvojeno iz ProjectSearchDialog.vue
// da bude testabilno bez montiranja komponente (E1).
//
// Task nema drugi dom osim TBI-a, aktivna faza pripada ploči, sve ostalo
// matičnom pogledu (bug uvijek u Bugovima jer taj registar prikazuje sve
// faze; ideja u Idejama jer taj pogled uključuje i gotove/odbijene, samo ne
// aktivne). Namjerno NE gleda je li stavka trenutno "na TBI ploči" preko
// accepted_at — za gotovu ideju koja je nekad bila prihvaćena to bi znalo
// odabrati TBI, gdje popis zatvorenih po zadanom skriva rezultat.
export const ACTIVE_STAGES = ['accepted', 'in_progress', 'testing']

export function tabForItem(item) {
  if (item.kind === 'task' || ACTIVE_STAGES.includes(item.stage)) return 'tbi'
  return item.kind === 'bug' ? 'bugs' : 'ideas'
}
