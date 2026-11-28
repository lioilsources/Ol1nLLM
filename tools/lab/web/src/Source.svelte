<script>
  import { st } from './lib/state.svelte.js';

  let open = $state({});
  let query = $state('');

  const runsOf = (fam) => (st.index?.runs || []).filter((r) => r.family === fam.key);
  const picked = (id) => st.recipe.source.runs.includes(id);

  function toggleRun(id) {
    const runs = st.recipe.source.runs;
    st.recipe.source.family = undefined;
    st.recipe.source.runs = picked(id) ? runs.filter((r) => r !== id) : [...runs, id];
  }

  function pickFamily(fam, minPics = 200) {
    st.recipe.source.family = undefined;
    st.recipe.source.runs = runsOf(fam)
      .filter((r) => r.pics >= minPics)
      .map((r) => r.id);
  }

  const matches = (r) => {
    const q = query.trim().toLowerCase();
    if (!q) return true;
    return r.id.includes(q) || r.models.some((m) => m.id.includes(q) || m.label.toLowerCase().includes(q));
  };

  // Families with a picked run open by themselves.
  $effect(() => {
    for (const f of st.index?.families || []) {
      if (runsOf(f).some((r) => picked(r.id))) open[f.key] = true;
    }
  });

  // Flows of the picked runs (not of the selection, or picking one would
  // hide the others).
  const flows = $derived.by(() => {
    const set = new Set();
    for (const r of st.index?.runs || []) if (picked(r.id)) Object.keys(r.flows || {}).forEach((f) => set.add(f));
    return [...set].sort().map((f) => ({ id: f, label: f }));
  });
  const flowSel = $derived(st.recipe.select.flow?.only?.[0] || '');
  function setFlow(f) {
    if (f) st.recipe.select.flow = { only: [f] };
    else delete st.recipe.select.flow;
  }

  const fmtDate = (s) => (s ? s.slice(0, 4) + '-' + s.slice(4, 6) + '-' + s.slice(6, 8) + ' ' + s.slice(9, 11) + ':' + s.slice(11, 13) : '');
</script>

<h2>1 Zdroj</h2>
<p class="hint">Rodina = běhy se stejnými prompty; jen ty jde poctivě dát vedle sebe.</p>
<input class="search" placeholder="hledat běh nebo model" bind:value={query} />

{#if flows.length > 1}
  <div class="flows">
    <span class="lbl">flow</span>
    <button class:on={!flowSel} onclick={() => setFlow('')}>všechny</button>
    {#each flows as f}
      <button class:on={flowSel === f.id} onclick={() => setFlow(f.id)}>{f.label}</button>
    {/each}
  </div>
{/if}

{#each st.index?.families || [] as fam}
  {@const runs = runsOf(fam).filter(matches)}
  {#if runs.length}
    <div class="family" class:active={runs.some((r) => picked(r.id))}>
      <button class="fam-head" onclick={() => (open[fam.key] = !open[fam.key])}>
        <span class="caret">{open[fam.key] ? '▾' : '▸'}</span>
        <b>{fam.prompts} {fam.scenes ? 'scén' : fam.prompts === 1 ? 'prompt' : 'promptů'}</b>
        <span class="dim">{fam.runs.length} běhů · {fam.models.length} modelů · {fam.flows.join(', ')}</span>
      </button>
      {#if open[fam.key]}
        <div class="fam-actions">
          <button onclick={() => pickFamily(fam)} title="běhy s aspoň 200 obrázky">vybrat celou rodinu</button>
          <button onclick={() => (st.recipe.source.runs = st.recipe.source.runs.filter((id) => !runs.some((r) => r.id === id)))}>nic</button>
        </div>
        {#each runs as r}
          <label class="run" class:on={picked(r.id)}>
            <input type="checkbox" checked={picked(r.id)} onchange={() => toggleRun(r.id)} />
            <span class="rid">{fmtDate(r.id)}</span>
            <span class="rcount" class:partial={r.pics < r.total}>{r.pics}/{r.total}</span>
            {#if r.status !== 'done'}<span class="status">{r.status}</span>{/if}
            {#if r.empty}<span class="warn" title="0bajtové soubory — chybějící obrázky">⚠ {r.empty}</span>{/if}
            {#if r.placeholder}<span class="status">nanečisto</span>{/if}
            <span class="models">{r.models.map((m) => m.label).join(', ')}</span>
          </label>
        {/each}
      {/if}
    </div>
  {/if}
{/each}

{#if st.coverage?.collisions}
  <p class="hint warn">
    {st.coverage.collisions} obrázků je ve víc bězích{st.coverage.differentSetups
      ? `, ${st.coverage.differentSetups} s jiným nastavením (seed, postava…)`
      : ''}; bere se první vybraný běh.
  </p>
{/if}
