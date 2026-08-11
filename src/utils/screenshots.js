import { supabase } from 'src/boot/supabase'
import { removeCachedImage } from 'src/utils/imageCache'

// Kad se screenshot stavke zamijeni novim, stari objekt u storageu više nitko ne
// referencira (put je jedinstven po uploadu) pa bi inače ostao zauvijek. Zove se
// tek nakon uspješnog UPDATE-a; neuspjeh brisanja ne smije srušiti spremanje.
export async function discardReplacedScreenshot(oldPath, newPath, bucket = 'chat-attachments') {
  if (!oldPath || !newPath || oldPath === newPath) return
  try {
    // E3: .remove() vraća { error }, ne baca — try/catch sam ovdje nikad
    // nije hvatao ništa stvarno.
    const { error } = await supabase.storage.from(bucket).remove([oldPath])
    if (error) console.warn('screenshot cleanup error:', error)
    await removeCachedImage(oldPath)
  } catch (e) {
    console.warn('screenshot cleanup error:', e)
  }
}
