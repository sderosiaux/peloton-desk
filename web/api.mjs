function failure(message, retryable = false) {
  return Object.assign(new Error(message), { retryable });
}

export function createAPI(fetcher = globalThis.fetch) {
  return async function api(path, body) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8000);
    try {
      let response;
      try {
        response = await fetcher('/api/' + path, {
          method: body === undefined ? 'GET' : 'POST', cache: 'no-store',
          headers: { 'Content-Type': 'application/json' }, signal: controller.signal,
          body: body === undefined ? undefined : JSON.stringify(body),
        });
      } catch {
        throw failure('Compagnon Mac injoignable · nouvelle tentative…', true);
      }
      let data;
      try { data = await response.json(); }
      catch { throw failure('Compagnon Mac en cours de démarrage · nouvelle tentative…', true); }
      if (!data || typeof data !== 'object' || Array.isArray(data)) {
        throw failure('Réponse du compagnon indisponible · nouvelle tentative…', true);
      }
      if (!response.ok) {
        throw failure(typeof data.error === 'string' ? data.error : 'Connexion au compagnon interrompue.', response.status >= 500);
      }
      return data;
    } finally { clearTimeout(timeout); }
  };
}
