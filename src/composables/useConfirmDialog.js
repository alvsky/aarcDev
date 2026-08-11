import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'

// I5: isti oblik potvrde za razorne (crvene) radnje ponavljao se kopipejstan
// na 8 mjesta (title/message/ok crveno/cancel) — jedno mjesto umjesto osam.
// Vraća Promise<boolean> umjesto .onOk() callbacka, da pozivatelj može
// jednostavno `if (!(await confirmDestructive(...))) return`.
export function useConfirmDialog() {
  const $q = useQuasar()
  const { t } = useI18n()

  function confirmDestructive({ title, message, okLabel }) {
    return new Promise((resolve) => {
      $q.dialog({
        title,
        message,
        ok: { label: okLabel ?? t('common.delete'), color: 'negative' },
        cancel: t('common.cancel'),
      })
        .onOk(() => resolve(true))
        .onCancel(() => resolve(false))
        .onDismiss(() => resolve(false))
    })
  }

  return { confirmDestructive }
}
