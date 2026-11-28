<script>
  import { clock } from './lib/api.js';
  import { st, AXES, axisName } from './lib/state.svelte.js';

  const r = $derived(st.recipe);
  const sb = $derived(st.plan?.storyboard);
  // The time axes the plan really used (it fills them in when left out).
  const effAxes = $derived(r.time.axes.length ? r.time.axes : sb?.recipe?.time?.axes || []);
  const multi = $derived(AXES.filter((a) => (st.coverage?.axes?.[a] || []).length > 1));
  const freeAxes = $derived(AXES.filter((a) => !effAxes.includes(a) && a !== r.frame.tiles && !r.output.per.includes(a)));

  function setTiles(a) {
    st.recipe.frame.tiles = a;
    st.recipe.time.axes = effAxes.filter((x) => x !== a);
    st.recipe.output.per = r.output.per.filter((x) => x !== a);
    if (!a) {
      st.recipe.time.loose = [];
    } else if (st.recipe.frame.fit === 'cover') st.recipe.frame.fit = 'contain';
  }
  function moveAxis(i, d) {
    const ax = [...effAxes];
    const j = i + d;
    if (j < 0 || j >= ax.length) return;
    [ax[i], ax[j]] = [ax[j], ax[i]];
    st.recipe.time.axes = ax;
    st.recipe.time.loose = r.time.loose.filter((l) => ax.indexOf(l) >= ax.length - r.time.loose.length);
  }
  function removeAxis(a) {
    st.recipe.time.axes = effAxes.filter((x) => x !== a);
    st.recipe.time.loose = r.time.loose.filter((x) => x !== a);
  }
  function addAxis(a, where) {
    if (!a) return;
    st.recipe.time.axes = effAxes.filter((x) => x !== a);
    st.recipe.output.per = r.output.per.filter((x) => x !== a);
    if (where === 'time') st.recipe.time.axes = [...st.recipe.time.axes, a];
    if (where === 'per') st.recipe.output.per = [...st.recipe.output.per, a];
  }
  // Loose = the inner end of the time axes; toggling moves the axis there.
  function toggleLoose(a) {
    if (r.time.loose.includes(a)) {
      st.recipe.time.loose = r.time.loose.filter((x) => x !== a);
      return;
    }
    st.recipe.time.axes = [...effAxes.filter((x) => x !== a), a];
    st.recipe.time.loose = [...r.time.loose, a];
    if (st.recipe.time.pair === 'order') st.recipe.time.pair = 'kind';
  }
  function setSelect(axis, v) {
    st.recipe.select[axis] = { only: [v] };
  }

  const split = $derived(r.output.split?.seconds || 0);
  function setSplit(sec) {
    sec = +sec;
    if (!sec) delete st.recipe.output.split;
    else st.recipe.output.split = { ...(r.output.split || {}), seconds: sec };
  }

  const captionMode = $derived(r.frame.captions.mode);
  function toggleCaption(a) {
    const axes = captionMode === 'list' ? [...(r.frame.captions.axes || [])] : [];
    const next = axes.includes(a) ? axes.filter((x) => x !== a) : [...axes, a];
    st.recipe.frame.captions = next.length ? { mode: 'list', axes: next } : { mode: 'none' };
  }
  const captionOn = (a) => captionMode === 'list' && (r.frame.captions.axes || []).includes(a);

  // „1 prompt = 12 s“: what the pace means for the outer axis.
  const outerInfo = $derived.by(() => {
    if (!sb || !effAxes.length) return '';
    const outer = effAxes[0];
    const groups = (sb.axes?.[outer] || []).length || 1;
    const per = sb.stats.slides / groups / r.time.rate;
    let s = `1 ${axisName(outer)} ≈ ${clock(per)}`;
    if (split) s += ` · díl ≈ ${Math.max(1, Math.floor(split / Math.max(per, 0.01)))}× ${axisName(outer)}`;
    return s;
  });

  const rates = [0.5, 1, 1.5, 2, 3, 4, 6, 8, 12, 15, 24, 30];

  // time.sync: cuts on the kick of a track from build/lab/_video/_audio.
  const tracks = $derived(st.index?.audio || []);
  const sync = $derived(r.time.sync);
  function setTrack(path) {
    if (!path) {
      delete st.recipe.time.sync;
      return;
    }
    st.recipe.time.sync = { every: 1, start: 0, breakdown: 2, ...(r.time.sync || {}), audio: path };
    st.recipe.time.fade = 0; // on the kick a hard cut
    delete st.recipe.output.maxSeconds;
  }
  const everies = [
    [0.25, 'šestnáctina'],
    [0.5, 'osmina'],
    [1, 'doba'],
    [2, 'půl taktu'],
    [4, 'takt'],
  ];

  // select.min_reaction travels like any select value: {only: ["0.15"]}.
  const minReaction = $derived(+(r.select.min_reaction?.only?.[0] || 0));
  function setMinReaction(v) {
    if (v > 0) st.recipe.select.min_reaction = { only: [String(v)] };
    else delete st.recipe.select.min_reaction;
  }
</script>

<section class="panel">
  <div class="panel-head"><h2>3 Skladba</h2>
    {#if st.planning}<span class="dim">plánuji…</span>{/if}
  </div>

  {#if st.planError}
    <div class="problems">
      {#if st.planError.missing?.length}
        {#each st.planError.missing as m}
          <div class="problem">
            <span>osa <b>{m.name}</b> má {m.values.length} hodnot a nemá roli:</span>
            <button onclick={() => addAxis(m.axis, 'time')}>do času</button>
            <button onclick={() => addAxis(m.axis, 'per')}>video na každou</button>
            <select onchange={(e) => setSelect(m.axis, e.currentTarget.value)}>
              <option value="">jen jedna…</option>
              {#each m.values as v}<option value={v.id}>{v.label}</option>{/each}
            </select>
          </div>
        {/each}
      {:else}
        <pre class="bad">{st.planError.error}</pre>
      {/if}
    </div>
  {/if}

  <div class="grid">
    <span class="lbl">snímek</span>
    <div class="ctl">
      <button class:on={!r.frame.tiles} onclick={() => setTiles('')}>jeden obrázek</button>
      <button class:on={!!r.frame.tiles} onclick={() => setTiles(r.frame.tiles || 'model')}>mřížka</button>
      {#if r.frame.tiles}
        dlaždice
        <select value={r.frame.tiles} onchange={(e) => setTiles(e.currentTarget.value)}>
          {#each AXES as a}<option value={a}>{axisName(a)}</option>{/each}
        </select>
        sloupce
        <select bind:value={st.recipe.frame.cols}>
          <option value={0}>auto</option>
          {#each [1, 2, 3, 4, 5, 6] as c}<option value={c}>{c}</option>{/each}
        </select>
        <label title="předloha běhu nebo fotka pozice restylu jako první dlaždice">
          <input type="checkbox" bind:checked={st.recipe.frame.reference} /> předloha
        </label>
        {#if sb?.layout}<span class="dim">{sb.layout.cols}×{sb.layout.rows}, obrázek {sb.layout.tileW} px</span>{/if}
      {:else}
        <select bind:value={st.recipe.frame.fit}>
          <option value="contain">celý na rozmazaném pozadí</option>
          <option value="cover">ořez na výšku</option>
        </select>
      {/if}
    </div>

    <span class="lbl">popisky</span>
    <div class="ctl">
      titulek
      <select bind:value={st.recipe.frame.title}>
        <option value="none">žádný</option>
        <option value="auto">auto</option>
        {#each AXES as a}<option value={a}>{axisName(a)}</option>{/each}
      </select>
      pod obrázkem
      {#each ['model', 'style', 'prompt'] as a}
        <button class:on={captionOn(a)} onclick={() => toggleCaption(a)}>{axisName(a)}</button>
      {/each}
    </div>

    <span class="lbl">čas</span>
    <div class="ctl axes">
      {#each effAxes as a, i}
        <span class="axis" class:loose={r.time.loose.includes(a)}>
          <button class="mini" onclick={() => moveAxis(i, -1)} disabled={i === 0} title="ven">‹</button>
          {axisName(a)}
          <button class="mini" onclick={() => moveAxis(i, 1)} disabled={i === effAxes.length - 1} title="dovnitř">›</button>
          {#if r.frame.tiles}
            <button class="mini" class:on={r.time.loose.includes(a)} onclick={() => toggleLoose(a)}
              title="volně: mezi dlaždicemi se smí lišit">~</button>
          {/if}
          <button class="mini" onclick={() => removeAxis(a)} title="odebrat">×</button>
        </span>
        {#if i < effAxes.length - 1}<span class="dim">→</span>{/if}
      {/each}
      <select value="" onchange={(e) => { addAxis(e.currentTarget.value, 'time'); e.currentTarget.value = ''; }}>
        <option value="">+ osa</option>
        {#each freeAxes as a}<option value={a}>{axisName(a)}{multi.includes(a) ? '' : ' (1 hodnota)'}</option>{/each}
      </select>
    </div>

    {#if r.time.loose.length}
      <span class="lbl">párování</span>
      <div class="ctl">
        <select bind:value={st.recipe.time.pair}>
          <option value="exact">jen společné styly</option>
          <option value="kind">+ stejný druh (kultura / umělec / médium)</option>
          <option value="order">+ zbytek v pořadí pickeru</option>
        </select>
      </div>
    {/if}

    {#if r.frame.tiles}
      <span class="lbl">neúplné</span>
      <div class="ctl">
        <label><input type="checkbox" bind:checked={st.recipe.time.complete} /> vynechat snímky s prázdnou dlaždicí</label>
      </div>
    {/if}

    <span class="lbl">reakce</span>
    <div class="ctl">
      <label title="vynechat obrázky, kde styl skoro nic nezměnil (barevná vzdálenost od obrázku bez stylu, metrics.json)">
        <input type="checkbox" checked={!!minReaction} onchange={(e) => setMinReaction(e.currentTarget.checked ? 0.15 : 0)} />
        jen kde styl něco udělal
      </label>
      {#if minReaction}
        ≥ <input type="number" min="0" max="1" step="0.05" value={minReaction} style="width:70px"
          onchange={(e) => setMinReaction(+e.currentTarget.value)} />
        {#if sb?.stats?.dropped?.reaction}<span class="dim">vyřazeno {sb.stats.dropped.reaction}</span>{/if}
      {/if}
    </div>

    <span class="lbl">tempo</span>
    <div class="ctl">
      <select value={sync?.audio || ''} onchange={(e) => setTrack(e.currentTarget.value)}
        title="střih na kopák skladby z build/lab/_video/_audio">
        <option value="">pevné tempo</option>
        {#each tracks as t}<option value={t.path}>♪ {t.name}</option>{/each}
        {#if sync?.audio && !tracks.some((t) => t.path === sync.audio)}<option value={sync.audio}>♪ {sync.audio}</option>{/if}
      </select>
      {#if !sync}
        <select bind:value={st.recipe.time.rate}>
          {#each rates as v}<option value={v}>{v}/s</option>{/each}
        </select>
      {/if}
      prolínačka
      <input type="range" min="0" max="0.9" step="0.05" bind:value={st.recipe.time.fade} />
      <span class="num">{(+r.time.fade).toFixed(2)}</span>
      {#if !sync}<span class="dim">{outerInfo}</span>{/if}
    </div>

    {#if sync}
      <span class="lbl">do hudby</span>
      <div class="ctl">
        snímek na
        <select bind:value={st.recipe.time.sync.every}>
          {#each everies as [v, l]}<option value={v}>{l}</option>{/each}
        </select>
        od
        <input type="number" min="0" step="1" style="width:64px" bind:value={st.recipe.time.sync.start} /> s
        <span title="kde kopák zmizí: snímek drží déle a prolíná se">breakdown</span>
        <select bind:value={st.recipe.time.sync.breakdown}>
          <option value={0}>beze změny</option>
          {#each [1, 2, 4, 8] as b}<option value={b}>{b} {b === 1 ? 'doba' : b < 5 ? 'doby' : 'dob'}</option>{/each}
        </select>
        posun
        <input type="number" step="0.01" style="width:64px" bind:value={st.recipe.time.sync.offset}
          title="posune všechny střihy o sekundy (+ později), kdyby oko nesouhlasilo" /> s
        {#if sb?.sync}
          <span class="dim">{sb.sync.bpm} BPM · {clock(sb.sync.duration)}{sb.sync.breakdowns?.length
            ? ' · breakdown ' + sb.sync.breakdowns.map((b) => clock(b[0])).join(', ') : ''}</span>
        {/if}
      </div>
    {/if}

    <span class="lbl">výstup</span>
    <div class="ctl">
      dělit po
      <select value={split} onchange={(e) => setSplit(e.currentTarget.value)}>
        <option value={0}>— (jedno video)</option>
        {#each [15, 30, 45, 60, 90, 170] as s}<option value={s}>{s} s</option>{/each}
      </select>
      {#if split}
        na
        <select value={r.output.split?.at || ''} onchange={(e) => (st.recipe.output.split.at = e.currentTarget.value || undefined)}>
          <option value="">vnější osa</option>
          {#each effAxes.filter((a) => !r.time.loose.includes(a)) as a}<option value={a}>{axisName(a)}</option>{/each}
        </select>
      {/if}
      video na
      <select value={r.output.per[0] || ''} onchange={(e) => addAxis(e.currentTarget.value, e.currentTarget.value ? 'per' : '')}>
        <option value="">—</option>
        {#each AXES.filter((a) => a !== r.frame.tiles) as a}<option value={a}>{axisName(a)}</option>{/each}
      </select>
      formát
      <select bind:value={st.recipe.output.size}>
        <option value="1080x1920">9:16</option>
        <option value="1080x1350">4:5</option>
        <option value="1080x1080">1:1</option>
      </select>
      <select bind:value={st.recipe.output.crf} title="kvalita kódování">
        <option value={18}>kvalita vysoká</option>
        <option value={23}>menší soubor</option>
      </select>
    </div>
  </div>

  {#if sb}
    <p class="summary">
      <b>{sb.videos.length}</b> {sb.videos.length === 1 ? 'video' : 'videí'} · {clock(sb.stats.seconds)} celkem
      {#if sb.videos.length > 1}· nejdelší {clock(Math.max(...sb.videos.map((v) => v.seconds)))}{/if}
    </p>
    {#each sb.warnings || [] as w}<p class="hint warn">⚠ {w}</p>{/each}
  {/if}
</section>
