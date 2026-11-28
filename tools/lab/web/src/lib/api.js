// The lab server's API. Non-GET requests carry the per-start token the
// server put into the page (as the rest of the lab does).
const meta = document.querySelector('meta[name=lab-token]');
const token = meta && !meta.content.startsWith('__') ? meta.content : '';

export class ApiError extends Error {
  constructor(message, body) {
    super(message);
    this.body = body;
  }
}

export async function api(path, { method = 'GET', body } = {}) {
  const headers = {};
  if (method !== 'GET') headers['X-Lab-Token'] = token;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  let res;
  try {
    res = await fetch(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  } catch {
    throw new ApiError('server neodpovídá — běží ještě `make lab`?');
  }
  const text = await res.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    if (!res.ok) throw new ApiError(text.trim() || `HTTP ${res.status}`);
  }
  if (!res.ok) throw new ApiError(data?.error || `HTTP ${res.status}`, data);
  return data;
}

export const post = (path, body) => api(path, { method: 'POST', body });

export function clock(sec) {
  const s = Math.round(sec || 0);
  if (s < 60) return `${s} s`;
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

export function mb(bytes) {
  return `${(bytes / 1e6).toFixed(bytes < 1e7 ? 1 : 0)} MB`;
}

export function debounce(fn, ms) {
  let t;
  return (...args) => {
    clearTimeout(t);
    t = setTimeout(() => fn(...args), ms);
  };
}
