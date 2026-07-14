const HASH_RUN_CHANGE_EVENT = 'simple-hash-run-change'

export const getRunIdFromHash = (): string | null => {
  if (typeof window === 'undefined') return null
  const hash = window.location.hash.replace('#', '')
  if (!hash.startsWith('run_')) return null
  return hash.replace('run_', '')
}

export const subscribeToRunHash = (onStoreChange: () => void): (() => void) => {
  window.addEventListener('hashchange', onStoreChange)
  window.addEventListener(HASH_RUN_CHANGE_EVENT, onStoreChange)
  return () => {
    window.removeEventListener('hashchange', onStoreChange)
    window.removeEventListener(HASH_RUN_CHANGE_EVENT, onStoreChange)
  }
}

export const setRunHash = (runId: string): void => {
  const newHash = `#run_${runId}`
  if (window.location.hash !== newHash) {
    window.history.pushState(null, '', newHash)
    window.dispatchEvent(new Event(HASH_RUN_CHANGE_EVENT))
  }
}

export const clearRunHash = (): void => {
  if (window.location.hash) {
    window.history.pushState(null, '', window.location.pathname + window.location.search)
    window.dispatchEvent(new Event(HASH_RUN_CHANGE_EVENT))
  }
}
