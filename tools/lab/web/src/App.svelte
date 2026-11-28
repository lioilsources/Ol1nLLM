<script>
  import { onMount } from 'svelte';
  import { api, post, debounce } from './lib/api.js';
  import { st, defaultRecipe, recipeJSON } from './lib/state.svelte.js';
  import Source from './Source.svelte';
  import Coverage from './Coverage.svelte';
  import Compose from './Compose.svelte';
  import Preview from './Preview.svelte';
  import Render from './Render.svelte';

  // Server JSON → the shape the form binds to (nulls to empty lists…).
  function normalize(r) {
    const d = defaultRecipe();
    const out = { ...d, ...r };
    out.source = { runs: [], ...(r.source || {}) };
    out.source.runs = out.source.runs || [];
    out.select = r.select || {};
    out.frame = { ...d.frame, ...(r.frame || {}) };
    out.frame.captions = r.frame?.captions?.mode ? r.frame.captions : { mode: 'none' };
    out.time = { ...d.time, ...(r.time || {}) };
    out.time.axes = out.time.axes || [];
    out.time.loose = out.time.loose || [];
    out.output = { ...d.output, ...(r.output || {}) };
    out.output.per = out.output.per || [];
    return out;
  }

  async function loadIndex(refresh = false) {
    try {
      st.index = await api('/api/video/index' + (refresh ? '?refresh=1' : ''));
    } catch (e) {
      st.error = e.message;
    }
  }

  export async function loadSaved() {
    try {
      st.saved = (await api('/api/video/recipes')) || [];
    } catch {}
  }

  onMount(async () => {
    await loadIndex();
    loadSaved();
    // /video/#run=<id>[,<id>…][&template=platno]: start from runs (the lab's
    // "video" link), optionally with a template applied.
    const m = location.hash.match(/run=([\w,-]+)/);
    if (m) st.recipe.source.runs = m[1].split(',');
    const t = location.hash.match(/template=(\w+)/);
    if (m && t) applyTemplate(t[1]);
  });

  const hasSource = () => st.recipe.source.runs.length > 0 || !!st.recipe.source.family;

  // Every change of the recipe replans (cheap: no pictures are read).
  const replan = debounce(async (recipe) => {
    st.planning = true;
    try {
      st.plan = await post('/api/video/plan', { recipe });
      st.planError = null;
    } catch (e) {
      st.plan = null;
      st.planError = e.body || { error: e.message };
    } finally {
      st.planning = false;
    }
  }, 300);

  $effect(() => {
    const r = recipeJSON();
    if (hasSource()) replan(r);
    else {
      st.plan = null;
      st.planError = null;
    }
  });

  // Coverage follows the source, the selection and the matrix axes.
  const recover = debounce(async (req) => {
    try {
      st.coverage = await post('/api/video/coverage', req);
    } catch (e) {
      st.coverage = { error: e.message };
    }
  }, 250);

  $effect(() => {
    const r = recipeJSON();
    if (!hasSource()) {
      st.coverage = null;
      return;
    }
    // The row axis ignores its own selection: a row switched off must stay
    // visible to be switched back on.
    const select = { ...r.select };
    delete select[st.covRows];
    recover({ source: r.source, select, rows: st.covRows, cols: st.covCols, count: 'prompt' });
  });

  async function applyTemplate(id) {
    if (!hasSource()) {
      st.error = 'Nejdřív vyber běhy vlevo.';
      return;
    }
    try {
      const r = recipeJSON();
      const res = await post('/api/video/template', { source: r.source, select: r.select, template: id, name: id });
      st.recipe = normalize(res.recipe);
      st.notes = res.notes || [];
      st.error = '';
    } catch (e) {
      st.error = e.message;
    }
  }

  async function openSaved(name) {
    if (!name) return;
    try {
      const res = await api('/api/video/recipes/' + encodeURIComponent(name));
      if (res.recipe) st.recipe = normalize(res.recipe);
      else st.error = res.error;
    } catch (e) {
      st.error = e.message;
    }
  }

  async function save() {
    try {
      await api('/api/video/recipes/' + encodeURIComponent(st.recipe.name), {
        method: 'PUT',
        body: { recipe: recipeJSON() },
      });
      await loadSaved();
      st.error = '';
    } catch (e) {
      st.error = e.message;
    }
  }

  async function toggleYaml() {
    st.showYaml = !st.showYaml;
    if (st.showYaml) {
      try {
        st.yaml = (await post('/api/video/yaml', { recipe: recipeJSON() })).yaml;
        st.yamlError = '';
      } catch (e) {
        st.yamlError = e.message;
      }
    }
  }

  async function applyYaml() {
    try {
      st.recipe = normalize((await post('/api/video/parse', { yaml: st.yaml })).recipe);
      st.yamlError = '';
      st.showYaml = false;
    } catch (e) {
      st.yamlError = e.message;
    }
  }
</script>

<header>
  <div class="brand"><a href="/">lab</a> <span>· video napříč běhy</span></div>
  <div class="templates">
    {#each st.index?.templates || [] as t}
      <button class="tmpl" title={t.What} onclick={() => applyTemplate(t.ID)}>{t.Name}</button>
    {/each}
  </div>
  <div class="recipe-bar">
    <input class="name" bind:value={st.recipe.name} spellcheck="false" title="jméno videa a složky v build/lab/_video" />
    <select onchange={(e) => openSaved(e.currentTarget.value)} title="uložené recepty">
      <option value="">otevřít…</option>
      {#each st.saved as s}<option value={s.name}>{s.name} ({s.videos})</option>{/each}
    </select>
    <button onclick={save} disabled={!hasSource()} title={hasSource() ? '' : 'nejdřív vyber běhy vlevo'}>Uložit</button>
    <button class:on={st.showYaml} onclick={toggleYaml} disabled={!hasSource() && !st.showYaml}
      title={hasSource() ? '' : 'nejdřív vyber běhy vlevo'}>YAML</button>
    <button onclick={() => loadIndex(true)} title="znovu načíst běhy z disku">↻</button>
  </div>
</header>

{#if st.error}<div class="banner bad" role="alert">{st.error} <button onclick={() => (st.error = '')}>×</button></div>{/if}
{#each st.notes as n}<div class="banner">{n}</div>{/each}
{#if st.index && !hasSource()}
  <div class="banner">Začni vlevo v <b>1 Zdroj</b>: zaškrtni běhy, nebo u rodiny „vybrat celou rodinu“. Pak nahoře šablona, nebo role os ve <b>3 Skladba</b>.</div>
{/if}

{#if st.showYaml}
  <section class="yaml">
    <textarea bind:value={st.yaml} spellcheck="false" rows="18"></textarea>
    <div class="row">
      <button onclick={applyYaml}>Použít</button>
      <span class="hint">Klíče: tools/lab/README.md, „Video napříč běhy“.</span>
      {#if st.yamlError}<pre class="bad">{st.yamlError}</pre>{/if}
    </div>
  </section>
{/if}

<main>
  <aside class="col-source"><Source /></aside>
  <section class="col-mid">
    <Coverage />
    <Compose />
  </section>
  <aside class="col-preview"><Preview /></aside>
</main>
<Render />
