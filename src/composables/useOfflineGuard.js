import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'
import { isOnline } from 'src/composables/useNetwork'

// Zajednička ograda za radnje koje offline tiho padnu na serveru (npr. brisanje —
// .delete() vrati { error } bez bacanja, pa se stavka makne lokalno i vrati kasnije).
// Vraća true ako je radnja blokirana (offline) i pritom prikaže poruku korisniku.
export function useOfflineGuard() {
  const $q = useQuasar()
  const { t } = useI18n()

  function blockedOffline(messageKey = 'common.offlineNoDelete') {
    if (isOnline()) return false
    $q.dialog({
      title: t('common.offlineTitle'),
      message: t(messageKey),
      ok: { label: t('common.confirm'), color: 'primary' },
    })
    return true
  }

  return { blockedOffline }
}
