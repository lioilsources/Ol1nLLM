<script>
  import { untrack } from 'svelte';
  import { api, clock } from './lib/api.js';
  import { st } from './lib/state.svelte.js';

  const W = 300; // preview width in CSS px
  const sb = $derived(st.plan?.storyboard);
  const n = $derived(st.plan?.slides || 0);
  const layout = $derived(sb?.layout);
  const k = $derived(layout ? W / layout.w : 1);

  let idx = $state(0);
  let prev = $state(-1);
  let playing = $state(false);
  let safe = $state(false);
  let picked = $state(null);

  // Slides come in pages of 200 per plan.
  let cache = $state({});
  let cachePlan = '';
  async function ensure(i) {
    const id = st.plan?.id;
    if (!id) return;
    if (id !== cachePlan) {
      cache = {};
      cachePlan = id;
    }
    const page = Math.floor(i / 200);
    if (cache['p' + page]) return;
    cache['p' + page] = 'loading';
    try {
      const res = await api(`/api/video/plans/${id}/slides?from=${page * 200}&to=${page * 200 + 200}`);
      res.slides.forEach((s, j) => (cache[res.from + j] = s));
    } catch {
      delete cache['p' + page];
    }
  }
  $effect(() => {
    if (idx >= n) idx = Math.max(0, n - 1);
    ensure(idx);
    ensure(idx + 1);
  });
  $effect(() => {
    st.plan?.id;
    prev = -1;
  });

  const slide = (i) => cache[i];
  const partOf = (i) => sb?.videos?.find((v) => i >= v.from && i < v.to);
  // With time.sync each slide has its own length and crossfade (part.times/fades).
  const fadeMs = $derived.by(() => {
    const p = partOf(idx);
    if (p?.times) {
      const k = idx - p.from;
      return Math.round(1000 * (p.fades?.[k] || 0) * (p.times[k + 1] - p.times[k]));
    }
    return Math.round((1000 * (st.recipe.time.fade || 0)) / Math.max(0.5, Math.min(st.recipe.time.rate, 12)));
  });

  function go(i) {
    i = Math.max(0, Math.min(n - 1, i));
    if (i === idx) return;
    prev = idx;
    idx = i;
  }

  // With music the track is the clock: the slide is whichever the audio time
  // falls into, so the preview cuts where the render will.
  let audio = $state();
  let muted = $state(false);
  const synced = $derived(!!(sb?.sync?.url && sb.videos?.[0]?.times));
  function slideAt(p, t) {
    let k = 0;
    while (k < p.to - p.from - 1 && p.times[k + 1] <= t) k++;
    return p.from + k;
  }
  $effect(() => {
    if (!playing || !synced || !audio) return;
    // Only the play button restarts this, not the slides it moves.
    let p = untrack(() => partOf(idx));
    if (!p) return;
    audio.currentTime = p.audioStart + p.times[untrack(() => idx) - p.from];
    audio.play().catch(() => (playing = false));
    let raf;
    const tick = () => {
      const t = audio.currentTime - p.audioStart;
      if (t >= p.times[p.to - p.from] || audio.ended) {
        const next = sb.videos.find((v) => v.from === p.to);
        if (!next) {
          playing = false;
          return;
        }
        p = next;
        go(p.from);
        audio.currentTime = p.audioStart;
      } else {
        const i = slideAt(p, t);
        if (i !== idx) go(i);
      }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => {
      cancelAnimationFrame(raf);
      audio.pause();
    };
  });

  // Real pace, capped at 12/s (a browser cannot keep up with 30 thumbnails a second).
  $effect(() => {
    if (!playing || synced) return;
    const rate = Math.max(0.5, Math.min(st.recipe.time.rate, 12));
    const t = setInterval(() => {
      if (idx >= n - 1) playing = false;
      else go(idx + 1);
    }, 1000 / rate);
    return () => clearInterval(t);
  });

  const part = $derived(partOf(idx));
  const media = (p) => '/media/' + p;
  const px = (v) => `${v * k}px`;
  const box = (r) => `left:${px(r.x)};top:${px(r.y)};width:${px(r.w)};height:${px(r.h)}`;
</script>

<h2>4 Náhled</h2>
{#if !sb || !layout}
  {#if st.planning}
    <p class="hint">plánuji…</p>
  {:else if st.planError}
    <p class="hint warn">Recept zatím nejde naplánovat — co chybí, je ve žlutém rámečku ve 3 Skladba
      (každá osa s víc hodnotami potřebuje roli), nebo zkus šablonu nahoře.</p>
  {:else if !st.recipe.source.runs.length && !st.recipe.source.family}
    <p class="hint">Vyber vlevo běhy; náhled se ukáže, jakmile jde recept naplánovat.</p>
  {:else}
    <p class="hint">Náhled se ukáže, jakmile jde recept naplánovat.</p>
  {/if}
{:else}
  <div class="frame" style="width:{W}px;height:{layout.h * k}px">
    {#each prev >= 0 && prev !== idx ? [prev, idx] : [idx] as i (i)}
      {@const s = slide(i)}
      <div class="layer" class:top={i === idx && prev >= 0} style="--fade:{fadeMs}ms">
        {#if s}
          {#if layout.single}
            {#if s.tiles[0]}
              {#if sb.recipe.frame.fit === 'cover'}
                <img class="cover" src={media(s.tiles[0].thumb)} alt="" />
              {:else}
                <img class="blur" src={media(s.tiles[0].thumb)} alt="" />
                <img class="contain" src={media(s.tiles[0].thumb)} alt="" />
              {/if}
            {/if}
            {#if s.title && layout.title}
              <div class="title" style={box(layout.title)}><span style="font-size:{layout.titleSize * k}px">{s.title}</span></div>
            {/if}
            {#if s.captions?.[0]?.length}
              <div class="labelbox" style="top:{px(layout.captionTop)}">
                {#each s.captions[0] as line, j}<div style="font-size:{(j ? 22 : 45) * k}px">{line}</div>{/each}
              </div>
            {/if}
          {:else}
            {#if s.title && layout.title}
              <div class="title" style={box(layout.title)}><span style="font-size:{layout.titleSize * k}px">{s.title}</span></div>
            {/if}
            {#each layout.tiles as t, j}
              {#if s.tiles[j]}
                <button class="tile" style={box(t.pic)} onclick={() => (picked = s.tiles[j])} title="{s.tiles[j].model} · {s.tiles[j].style}">
                  <img src={media(s.tiles[j].thumb)} alt="" />
                </button>
              {:else}
                <div class="tile empty" style={box(t.pic)}></div>
              {/if}
              {#if t.caption}
                <div class="caption" style={box(t.caption)}>
                  {#each s.captions?.[j] || [] as line, li}
                    <div style="font-size:{(li ? layout.captionSize2 : layout.captionSize) * k}px">{line}</div>
                  {/each}
                </div>
              {/if}
            {/each}
          {/if}
        {:else}
          <div class="loading">…</div>
        {/if}
      </div>
    {/each}
    {#if safe}
      <div class="safe top" style="height:{0.085 * layout.h * k}px"></div>
      <div class="safe bottom" style="height:{0.12 * layout.h * k}px"></div>
    {/if}
  </div>

  <div class="transport">
    <button onclick={() => (playing = !playing)}>{playing ? '❚❚' : '▶'}</button>
    <button onclick={() => go(idx - 1)}>‹</button>
    <button onclick={() => go(idx + 1)}>›</button>
    <span class="num">{idx + 1}/{n}</span>
    {#if synced}
      <button class="mini" class:on={!muted} onclick={() => (muted = !muted)} title="zvuk náhledu">{muted ? '🔇' : '♪'}</button>
      <span class="dim">{sb.sync.bpm} BPM</span>
    {/if}
  </div>
  {#if synced}<audio bind:this={audio} src={sb.sync.url} preload="auto" {muted}></audio>{/if}
  <div class="scrub">
    <input type="range" min="0" max={Math.max(0, n - 1)} value={idx} oninput={(e) => go(+e.currentTarget.value)} />
    <div class="ticks">
      {#each sb.videos as v}
        {#if v.from > 0}<span class="tick" style="left:{(100 * v.from) / Math.max(1, n - 1)}%"></span>{/if}
      {/each}
    </div>
  </div>
  {#if part}
    <p class="dim">{part.name}.mp4 · {clock(part.seconds)} · snímek {idx - part.from + 1}/{part.to - part.from}
      {#if part.times}· {(part.times[idx - part.from + 1] - part.times[idx - part.from]).toFixed(2)} s{/if}</p>
  {/if}
  <label class="dim"><input type="checkbox" bind:checked={safe} /> bezpečné zóny TikToku / Shorts</label>
  {#if picked}
    <p class="picked">
      {picked.model} · {picked.style}<br /><span class="dim">{picked.run} / {picked.cell}</span>
      <button class="mini" onclick={() => (picked = null)}>×</button>
    </p>
  {/if}
  <p class="hint">Náhled kreslí z náhledů běhu (320 px); rozložení je totéž, jaké použije render.</p>
{/if}
