<script>
  import { post } from './lib/api.js';
  import { st, axisName, recipeJSON } from './lib/state.svelte.js';

  const cov = $derived(st.coverage?.coverage);
  const axes = $derived(st.coverage?.axes || {});
  const multiAxes = $derived(Object.keys(axes).filter((a) => (axes[a] || []).length > 1));

  // The model selection is the tile order: rows are toggled in and out.
  const rowSel = $derived(st.recipe.select[st.covRows]?.only || []);
  function toggleRow(id) {
    const a = st.covRows;
    const all = (axes[a] || []).map((v) => v.id);
    let only = rowSel.length ? [...rowSel] : [...all];
    only = only.includes(id) ? only.filter((x) => x !== id) : [...only, id];
    if (only.length === all.length) delete st.recipe.select[a];
    else st.recipe.select[a] = { ...(st.recipe.select[a] || {}), only };
  }
  const rowOn = (id) => !rowSel.length || rowSel.includes(id);

  // Columns grouped by style kind, so 300 styles read as three bands.
  const groups = $derived.by(() => {
    if (!cov) return [];
    const out = [];
    cov.cols.forEach((c, j) => {
      const k = st.covCols === 'style' ? (c.id === '__baseline' ? 'bez stylu' : kindName(c.kind)) : '';
      if (!out.length || out[out.length - 1].kind !== k) out.push({ kind: k, cols: [] });
      out[out.length - 1].cols.push(j);
    });
    return out;
  });
  function kindName(k) {
    return { culture: 'kultury', artist: 'umělci', medium: 'média' }[k] || 'jiné';
  }
  const shade = (n) => {
    if (!cov?.of || !n) return 'transparent';
    const f = n / cov.of;
    return `hsl(${150 * f} 60% ${18 + 32 * f}%)`;
  };
  const rowTotal = (i) => cov.cells[i].reduce((a, n) => a + n, 0);

  let sugg = $state(null);
  let suggBusy = $state(false);
  async function suggest() {
    suggBusy = true;
    try {
      const r = recipeJSON();
      const tiles = r.frame.tiles || 'model';
      const select = { ...r.select };
      delete select[tiles];
      sugg = await post('/api/video/suggest', {
        source: r.source,
        select,
        tiles,
        loose: r.time.loose?.length ? r.time.loose : ['style'],
        k: 6,
        top: 2,
      });
    } catch (e) {
      sugg = { error: e.message };
    } finally {
      suggBusy = false;
    }
  }
  function useSuggestion(s) {
    const tiles = st.recipe.frame.tiles || 'model';
    st.recipe.frame.tiles = tiles;
    st.recipe.select[tiles] = { only: [...s.values] };
  }

  const stats = $derived(st.plan?.storyboard?.stats);
  const match = $derived(stats?.match || {});
  const matchTotal = $derived((match.exact || 0) + (match.kind || 0) + (match.order || 0));
  const pct = (n) => Math.round((100 * (n || 0)) / Math.max(1, matchTotal));
</script>

<section class="panel">
  <div class="panel-head">
    <h2>2 Pokrytí</h2>
    <label>řádky
      <select bind:value={st.covRows}>
        {#each multiAxes.length ? multiAxes : ['model'] as a}<option value={a}>{axisName(a)}</option>{/each}
      </select>
    </label>
    <label>sloupce
      <select bind:value={st.covCols}>
        {#each multiAxes.length ? multiAxes : ['style'] as a}<option value={a}>{axisName(a)}</option>{/each}
      </select>
    </label>
    <span class="dim">buňka = u kolika promptů z {cov?.of ?? '–'} je obrázek</span>
  </div>

  {#if st.coverage?.error}
    <p class="bad">{st.coverage.error}</p>
  {:else if !cov}
    <p class="hint">Vyber vlevo běhy — tady se ukáže, který model má který styl.</p>
  {:else}
    <div class="heat">
      <div class="heat-row heat-head">
        <span class="rowlabel"></span>
        <div class="cells">
          {#each groups as g}
            <span class="band" style="flex:{g.cols.length}">{g.kind}</span>
          {/each}
        </div>
      </div>
      {#each cov.rows as row, i}
        <div class="heat-row" class:off={!rowOn(row.id)}>
          <label class="rowlabel">
            <input type="checkbox" checked={rowOn(row.id)} onchange={() => toggleRow(row.id)} />
            {row.label} <span class="dim">{rowTotal(i)}</span>
          </label>
          <div class="cells">
            {#each cov.cells[i] as n, j}
              <span class="cell" style="background:{shade(n)}" title="{row.label} · {cov.cols[j].label}: {n}/{cov.of}"></span>
            {/each}
          </div>
        </div>
      {/each}
    </div>
  {/if}

  {#if stats}
    <p class="summary">
      <b>{stats.slides}</b> snímků ·
      vyřazeno neúplných {stats.dropped?.incomplete || 0}{#if stats.dropped?.empty_file}, prázdných souborů {stats.dropped.empty_file}{/if}
      {#if matchTotal}
        · shoda stylu: <b>{pct(match.exact)} %</b> přesná, <b>{pct(match.kind)} %</b> stejný druh, {pct(match.order)} % jiná
      {/if}
    </p>
  {/if}

  <div class="row">
    <button onclick={suggest} disabled={!cov || suggBusy}>{suggBusy ? 'počítám…' : 'Navrhni kombinace'}</button>
    <span class="hint">které {axisName(st.recipe.frame.tiles || 'model')} dát vedle sebe, aby bylo nejvíc úplných snímků</span>
  </div>
  {#if sugg?.error}<p class="bad">{sugg.error}</p>{/if}
  {#if sugg?.rows}
    {#if sugg.note}<p class="hint">{sugg.note}</p>{/if}
    <table class="sugg">
      <thead><tr><th>dlaždic</th><th>striktně</th><th>volně</th><th>kombinace</th></tr></thead>
      <tbody>
        {#each sugg.rows as row}
          {#each [...row.strict, ...row.loose.filter((l) => !row.strict.some((s) => s.values.join() === l.values.join()))] as s}
            <tr onclick={() => useSuggestion(s)} title="použít">
              <td>{row.k}</td><td>{s.strict}</td><td>{s.loose}</td><td>{s.labels.join(' + ')}</td>
            </tr>
          {/each}
        {/each}
      </tbody>
    </table>
    <p class="hint">Striktně = stejný prompt i styl. Volně = stejný prompt, styl se smí lišit (mix). Klik nastaví dlaždice.</p>
  {/if}
</section>
