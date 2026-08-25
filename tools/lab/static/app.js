// lab — plan a batch, watch it fill in, read what was actually wired.
// No build step on purpose: the whole UI ships inside the Go binary.
const TOKEN = document.querySelector('meta[name=lab-token]').content;
const $ = (id) => document.getElementById(id);

const state = {
  config: null,
  models: new Set(),
  styles: new Set(),
  flows: new Set(['repose']),
  poseMode: 'none',
  poseId: '',
  ref: null,
  runId: null,
  run: null,
  manifest: null,
  metrics: null,
  es: null,
};

const FLOW_LABEL = {
  txt2img: 'txt2img',
  img2img: 'img2img',
  repose: 'zachovej pózu',
};

async function api(path, opts = {}) {
  const res = await fetch(path, {
    ...opts,
    headers: { 'X-Lab-Token': TOKEN, ...(opts.body ? { 'Content-Type': 'application/json' } : {}), ...(opts.headers || {}) },
  });
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = { error: text }; }
  if (!res.ok) throw new Error((data && data.error) || res.statusText);
  return data;
}

// ── header lamps ───────────────────────────────────────────
async function refreshHealth() {
  let h;
  try { h = await api('/api/health'); } catch { return; }
  const lamps = [
    ['flutter', h.flutter.ok, h.flutter.ok ? h.flutter.msg.split('•')[0].trim() : h.flutter.msg],
    ['CF Access', h.cfAccess, h.cfAccess ? 'creds načtené' : 'chybí v .env.local'],
    ['ComfyUI', h.comfyOk !== false && h.cfAccess,
      h.queue ? `fronta ${h.queue.running}/${h.queue.pending}` : (h.comfyErr || 'nepřipojeno')],
  ];
  $('lamps').innerHTML = lamps.map(([name, ok, detail]) =>
    `<span class="lamp ${ok ? 'ok' : 'bad'}" title="${esc(detail)}">${name}</span>`).join('');
  if (h.forceDry) $('mode').value = 'dry', $('mode').disabled = true;
}

// ── plan form ──────────────────────────────────────────────
async function loadConfig() {
  const cfg = await api('/api/config');
  state.config = cfg;

  $('models').innerHTML = cfg.models.map((m) => `
    <button class="chip" data-model="${esc(m.id)}" aria-pressed="false">
      ${esc(m.label)}<small>${esc(m.styleNote || '')}</small>
    </button>`).join('');
  $('models').onclick = (e) => toggle(e, 'model', state.models);

  $('styles').innerHTML = cfg.styles.map((s) =>
    `<button class="chip" data-style="${esc(s.id)}" aria-pressed="false" title="${esc(s.block)}">${esc(s.label)}</button>`).join('');
  $('styles').onclick = (e) => toggle(e, 'style', state.styles);

  $('flows').innerHTML = Object.entries(FLOW_LABEL).map(([id, label]) =>
    `<button class="chip" data-flow="${id}" data-flowsel="${id}" aria-pressed="${state.flows.has(id)}">${label}</button>`).join('');
  $('flows').onclick = (e) => toggle(e, 'flowsel', state.flows);

  $('posemode').innerHTML = [
    ['none', 'bez pózy'], ['depth', 'depth z předlohy'], ['template', 'šablona kostry'],
  ].map(([id, label]) =>
    `<button class="chip" data-pose="${id}" aria-pressed="${state.poseMode === id}">${label}</button>`).join('');
  $('posemode').onclick = (e) => {
    const b = e.target.closest('[data-pose]');
    if (!b) return;
    state.poseMode = b.dataset.pose;
    [...$('posemode').children].forEach((c) => c.setAttribute('aria-pressed', c === b));
    $('poses').hidden = state.poseMode !== 'template';
    updatePoseHint();
    estimate();
  };

  $('poses').innerHTML = cfg.poses.map((p) =>
    `<button data-poseid="${esc(p.id)}" aria-pressed="false" title="${esc(p.label)}">
       <img src="/media/_poses/${esc(p.id)}.png" alt="${esc(p.label)}"></button>`).join('');
  $('poses').onclick = (e) => {
    const b = e.target.closest('[data-poseid]');
    if (!b) return;
    state.poseId = b.dataset.poseid;
    [...$('poses').children].forEach((c) => c.setAttribute('aria-pressed', c === b));
    estimate();
  };
  updatePoseHint();
}

function toggle(e, attr, set) {
  const b = e.target.closest(`[data-${attr}]`);
  if (!b) return;
  const v = b.dataset[attr];
  if (set.has(v)) set.delete(v); else set.add(v);
  b.setAttribute('aria-pressed', set.has(v));
  estimate();
}

function updatePoseHint() {
  const t = {
    none: 'img2img si u SDXL modelů drží pózu sám (auto-depth 0.7).',
    depth: 'Hloubková mapa z předlohy. Drží stanoviště i směr pohledu — na rozdíl od kostry.',
    template: 'Kostra na plnou sílu. Jen SDXL modely; ostatní se přeskočí a řekne se to.',
  }[state.poseMode];
  $('posehint').textContent = t;
}

$('sweepTarget').onchange = () => {
  const opt = $('sweepTarget').selectedOptions[0];
  $('sweephint').innerHTML = opt.dataset.preset
    ? '<span class="warnline">Přebíjí preset modelu — kalibrace (třeba 6 kroků u Lightningu) je pryč, takže výsledek není verdikt o modelu.</span>'
    : (opt.value ? 'Parametr flow — chová se jako v appce.' : '');
  estimate();
};

$('ref').onchange = async () => {
  const file = $('ref').files[0];
  if (!file) return;
  $('refpreview').innerHTML = '<p class="hint">nahrávám…</p>';
  try {
    const res = await fetch('/api/upload-ref', {
      method: 'PUT', headers: { 'X-Lab-Token': TOKEN }, body: file,
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error);
    state.ref = data;
    $('refpreview').innerHTML = data.thumb
      ? `<img src="${esc(data.thumb)}" alt="předloha" style="width:100%;border-radius:4px;margin-bottom:8px">`
      : '<p class="hint">nahráno</p>';
  } catch (err) {
    $('refpreview').innerHTML = `<p class="hint danger">${esc(err.message)}</p>`;
  }
  estimate();
};

function spec() {
  const values = $('sweepValues').value.trim();
  const target = $('sweepTarget').value;
  return {
    title: ($('prompts').value.split('\n')[0] || 'běh').slice(0, 60),
    models: [...state.models],
    prompts: $('prompts').value.split('\n').map((s) => s.trim()).filter(Boolean),
    styles: [...state.styles],
    flows: [...state.flows],
    refName: state.ref?.refName || '',
    refFile: state.ref?.localPath || '',
    poseMode: state.poseMode,
    poseId: state.poseId,
    poseName: state.poseName || '',
    seed: Number($('seed').value) || 777,
    batch: Number($('batch').value) || 1,
    negative: $('negative').value.trim(),
    editDenoise: Number($('editDenoise').value) || 0,
    sweep: target && values ? `${target}=${values}` : '',
    dry: $('mode').value === 'dry',
  };
}

let estTimer;
function estimate() {
  clearTimeout(estTimer);
  estTimer = setTimeout(async () => {
    try {
      const e = await api('/api/estimate', { method: 'POST', body: JSON.stringify(spec()) });
      const blocked = e.blockers.length > 0;
      $('startbtn').disabled = blocked;
      $('estimate').innerHTML = blocked
        ? `<span class="danger">${e.blockers.map(esc).join(' · ')}</span>`
        : `${e.cells} buněk${e.variants > 1 ? ` (${e.variants} variant)` : ''} · ~${e.estMinutes.toFixed(0)} min`
          + (e.warnings.length ? `<br><span class="warnline">${e.warnings.map(esc).join(' · ')}</span>` : '');
    } catch (err) {
      $('estimate').innerHTML = `<span class="danger">${esc(err.message)}</span>`;
    }
  }, 220);
}
['prompts', 'seed', 'batch', 'negative', 'editDenoise', 'sweepValues', 'mode'].forEach((id) =>
  $(id).addEventListener('input', estimate));

$('startbtn').onclick = async () => {
  $('startbtn').disabled = true;
  try {
    const { runId } = await api('/api/runs', { method: 'POST', body: JSON.stringify(spec()) });
    openRun(runId);
  } catch (err) {
    $('estimate').innerHTML = `<span class="danger">${esc(err.message)}</span>`;
    $('startbtn').disabled = false;
  }
};

// ── run view ───────────────────────────────────────────────
async function refreshRuns() {
  const runs = await api('/api/runs');
  $('runlist').innerHTML = runs.map((r) =>
    `<button data-run="${esc(r.id)}" class="${r.id === state.runId ? 'active' : ''}">
       ${esc(r.id)} · ${esc(r.status)} ${r.total ? `· ${r.done}/${r.total}` : ''}</button>`).join('');
  $('runlist').onclick = (e) => {
    const b = e.target.closest('[data-run]');
    if (b) openRun(b.dataset.run);
  };
}

async function openRun(id) {
  state.runId = id;
  location.hash = `#/run/${id}`;
  if (state.es) state.es.close();
  const data = await api(`/api/runs/${id}`);
  state.run = data.state;
  state.manifest = data.manifest;
  state.metrics = data.metrics;
  render();
  refreshRuns();
  state.es = new EventSource(`/api/runs/${id}/events`);
  state.es.onmessage = (ev) => {
    state.run = JSON.parse(ev.data);
    if (state.run.status !== 'planning' && !state.manifest) {
      api(`/api/runs/${id}`).then((d) => {
        state.manifest = d.manifest; state.metrics = d.metrics; render();
      });
    } else { render(); }
    refreshRuns();
  };
}

function render() {
  const run = state.run, man = state.manifest;
  if (!run) return;
  if (!man) {
    $('content').innerHTML = `<div class="empty"><h2>${esc(run.status)}</h2>
      <p>${esc(run.message || 'pracuje se…')}</p></div>`;
    return;
  }
  const models = man.models.filter((m) => man.cells.some((c) => c.model === m.id));
  // Rows are flow → prompt → style; models are the bounded axis, so they are
  // the columns. Flows get their own band because their metrics live on
  // different scales and mixing them in one column would make numbers lie.
  const rows = [];
  for (const flow of [...new Set(man.cells.map((c) => c.flow))]) {
    rows.push({ band: flow });
    const inFlow = man.cells.filter((c) => c.flow === flow);
    for (const p of [...new Set(inFlow.map((c) => c.promptIndex))].sort()) {
      for (const style of [...new Set(inFlow.filter((c) => c.promptIndex === p).map((c) => c.style))]) {
        rows.push({ flow, prompt: p, style });
      }
    }
  }

  const head = `<thead><tr><th></th>${models.map((m) => `
    <th><div class="mname">${esc(m.label)}</div>
        <div class="mnote">${esc(m.styleNote || '')}</div></th>`).join('')}</tr></thead>`;

  const body = rows.map((r) => {
    if (r.band) {
      return `<tr class="band"><th colspan="${models.length + 1}">
        <span class="flowtag" data-flow="${esc(r.band)}">${esc(FLOW_LABEL[r.band] || r.band)}</span></th></tr>`;
    }
    const label = r.style === '__baseline'
      ? '<span class="styleid">bez stylu (baseline)</span>'
      : `<span class="styleid">${esc(styleLabel(r.style))}</span>`;
    const promptLine = man.prompts.length > 1
      ? `<div class="promptline">${esc((man.prompts[r.prompt] || '').slice(0, 70))}</div>` : '';
    const cols = models.map((m) => {
      const cells = man.cells.filter((c) => c.flow === r.flow && c.model === m.id
        && c.promptIndex === r.prompt && c.style === r.style);
      if (!cells.length) {
        const skip = (man.skipped || []).find((s) => s.cell.includes(`__${m.id}__`));
        return `<td><div class="skiprow" title="${esc(skip ? skip.reason : '')}">—</div></td>`;
      }
      return `<td><div class="cellstrip">${cells.map(cellHTML).join('')}</div></td>`;
    }).join('');
    return `<tr><th class="rowhead">${label}${promptLine}</th>${cols}</tr>`;
  }).join('');

  const skipped = (man.skipped || []).length
    ? `<p class="hint">Přeskočeno ${man.skipped.length} buněk: ${
        esc([...new Set(man.skipped.map((s) => s.reason))].join(' · '))}</p>` : '';

  $('content').innerHTML =
    `<p class="hint">${esc(run.status)} — ${esc(run.message || '')}${
      run.total ? ` · ${run.done}/${run.total}` : ''}${
      run.dry ? ' · nanečisto (placeholdery)' : ''}</p>
     ${skipped}
     <div class="tablewrap"><table class="matrix">${head}<tbody>${body}</tbody></table></div>`;

  $('content').onclick = (e) => {
    const b = e.target.closest('[data-cell]');
    if (b) openCell(b.dataset.cell);
  };
}

function cellHTML(c) {
  const st = (state.run.cells || {})[c.id] || { status: 'pending' };
  const src = st.status === 'done' ? `/media/${state.runId}/thumb/${encodeURIComponent(c.id)}.jpg` : '';
  const variant = c.variant ? `<span class="vlabel">${esc(c.variant.value)}</span>` : '';
  const badge = c.presetOverridden ? '<span class="badge" title="preset přebit">≠</span>' : '';
  return `<button class="cell" data-cell="${esc(c.id)}" data-status="${st.status}"
      title="${esc(st.error || c.id)}">
      ${src ? `<img loading="lazy" src="${src}" alt="">` : ''}${variant}${badge}</button>`;
}

function styleLabel(id) {
  const s = (state.config?.styles || []).find((x) => x.id === id);
  return s ? s.label : id;
}

// ── drawer: parameters, metrics, and the wiring chain ──────
async function openCell(id) {
  const d = $('drawer');
  d.hidden = false; d.classList.add('show');
  $('drawerbody').innerHTML = '<p class="hint">načítám…</p>';
  let data;
  try { data = await api(`/api/runs/${state.runId}/cell/${encodeURIComponent(id)}`); }
  catch (err) { $('drawerbody').innerHTML = `<p class="danger">${esc(err.message)}</p>`; return; }
  const c = data.cell;
  const st = (state.run.cells || {})[id] || {};
  const m = (state.metrics?.cells || {})[id] || {};
  const groupKey = `${c.flow}|${c.model}|p${c.promptIndex}`;
  const g = (state.metrics?.groups || {})[groupKey];

  const metrics = [
    m.reaction != null ? metric(m.reaction.toFixed(3), 'reakce na styl') : '',
    m.neighbourDelta != null ? metric(m.neighbourDelta.toFixed(3), 'změna proti předchozí hodnotě') : '',
    g ? metric(g.spread.toFixed(3), `rozptyl stylů (${g.n})`) : '',
  ].filter(Boolean).join('');

  $('drawerbody').innerHTML = `
    <h2>${esc(c.modelLabel)} · ${esc(c.style === '__baseline' ? 'bez stylu' : styleLabel(c.style))}</h2>
    <div class="sub">${esc(c.id)}${c.variant ? ` · ${esc(c.variant.label)}=${esc(c.variant.value)}` : ''}</div>
    ${st.status === 'done' ? `<img class="full" src="/media/${state.runId}/img/${encodeURIComponent(id)}.png" alt="">` : ''}
    ${st.error ? `<p class="danger">${esc(st.error)}</p>` : ''}
    ${metrics ? `<div class="metricrow">${metrics}</div>
      <p class="hint">${esc(state.config.copy.metrics.text)}</p>` : ''}
    ${c.presetOverridden ? `<p class="hint warnline">${esc(state.config.copy.preset_overridden.text)}</p>` : ''}
    <dl class="kv">
      <dt>prompt</dt><dd>${esc(c.prompt || '—')}</dd>
      <dt>negativ</dt><dd>${esc(c.negative || '—')}</dd>
      ${Object.entries(c.params || {}).filter(([, v]) => v !== null && v !== '')
        .map(([k, v]) => `<dt>${esc(k)}</dt><dd>${esc(String(v))}</dd>`).join('')}
    </dl>
    <p class="grouplabel" style="margin-top:18px">co je zapojené</p>
    <div class="chain">${data.explain.map(chainNode).join('')}</div>
    <details class="raw"><summary>workflow JSON</summary>
      <pre>${esc(JSON.stringify(data.workflow, null, 1))}</pre></details>`;
}

function metric(value, label) {
  return `<div class="metric"><b>${esc(value)}</b><span>${esc(label)}</span></div>`;
}

// One link of the signal chain: a pill for the node, a cable down to the next.
function chainNode(s, i, all) {
  const vals = Object.entries(s.values || {})
    .map(([k, v]) => `${k}=${typeof v === 'string' && v.length > 60 ? v.slice(0, 60) + '…' : v}`)
    .join('  ');
  return `<div class="link">
    <div class="cable">${i < all.length - 1 ? '<i></i>' : ''}</div>
    <div class="node ${s.injected ? 'injected' : ''}">
      <div class="top">
        <span class="lbl">${esc(s.label)}</span>
        ${s.injected ? '<span class="tag">vloženo appkou</span>' : ''}
        <span class="cls">${esc(s.class)}</span>
      </div>
      ${vals ? `<div class="vals">${esc(vals)}</div>` : ''}
      ${s.note ? `<div class="note">${esc(s.note)}</div>` : ''}
    </div></div>`;
}

$('closedrawer').onclick = () => {
  $('drawer').classList.remove('show');
  setTimeout(() => { $('drawer').hidden = true; }, 200);
};
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') $('closedrawer').click(); });

function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

(async function boot() {
  await refreshHealth();
  try { await loadConfig(); } catch (err) {
    $('estimate').innerHTML = `<span class="danger">${esc(err.message)}</span>`;
  }
  await refreshRuns();
  const m = location.hash.match(/#\/run\/(.+)/);
  if (m) openRun(m[1]);
  estimate();
  setInterval(refreshHealth, 30000);
})();
