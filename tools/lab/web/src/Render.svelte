<script>
  import { onMount } from 'svelte';
  import { api, post, clock, mb } from './lib/api.js';
  import { st, recipeJSON } from './lib/state.svelte.js';

  let jobs = $state([]);
  let outputs = $state([]);
  let error = $state('');
  let playing = $state('');
  let copied = $state(false);

  const sb = $derived(st.plan?.storyboard);
  // Rough: the Go renderer did ~2.4 s of video per second of wall time on a
  // grid, ~0.5 s per second on a stroboscope (one picture a frame).
  const estimate = $derived(sb ? sb.stats.seconds / (sb.layout?.single ? 1.5 : 2.4) : 0);

  async function refresh() {
    try {
      jobs = (await api('/api/video/jobs')) || [];
      outputs = (await api('/api/video/outputs')) || [];
    } catch (e) {
      error = e.message;
    }
  }
  onMount(() => {
    refresh();
    for (const j of jobs) if (j.status === 'running' || j.status === 'queued') follow(j.id);
  });

  function follow(id) {
    const es = new EventSource('/api/video/jobs/' + id);
    es.onmessage = (ev) => {
      const j = JSON.parse(ev.data);
      const i = jobs.findIndex((x) => x.id === j.id);
      if (i >= 0) jobs[i] = j;
      else jobs = [j, ...jobs];
      if (j.status === 'done' || j.status === 'failed' || j.status === 'cancelled') {
        es.close();
        refresh();
      }
    };
    es.onerror = () => es.close();
  }

  async function render(draft = false, only = []) {
    error = '';
    try {
      const j = await post('/api/video/render', { recipe: recipeJSON(), draft, only });
      jobs = [j, ...jobs];
      follow(j.id);
    } catch (e) {
      error = e.message;
    }
  }
  async function cancel(id) {
    try {
      await api('/api/video/jobs/' + id, { method: 'DELETE' });
    } catch (e) {
      error = e.message;
    }
  }
  async function reveal(set, file) {
    try {
      await post('/api/video/reveal', { path: set + '/' + file });
    } catch (e) {
      error = e.message;
    }
  }
  async function copyCommand() {
    const cmd = `make lab-video RECIPE=build/lab/_video/${st.recipe.name}/recipe.yaml`;
    try {
      await navigator.clipboard.writeText(cmd);
      copied = true;
      setTimeout(() => (copied = false), 1500);
    } catch {
      error = cmd;
    }
  }
  const pct = (j) => (j.progress?.frames ? Math.round((100 * j.progress.frame) / j.progress.frames) : 0);
</script>

<section class="render">
  <div class="panel-head">
    <h2>5 Render</h2>
    {#if sb}
      <span class="dim">{sb.videos.length} {sb.videos.length === 1 ? 'video' : 'videí'} · {clock(sb.stats.seconds)} · odhad {clock(estimate)}</span>
    {/if}
    <button class="primary" disabled={!sb} onclick={() => render(false)}>Renderovat</button>
    <button disabled={!sb} onclick={() => render(true)} title="z náhledů 320 px — rychlý koncept">Koncept</button>
    <button onclick={copyCommand}>{copied ? 'zkopírováno' : 'Kopírovat příkaz'}</button>
    <span class="hint">výstup: build/lab/_video/{st.recipe.name}/</span>
  </div>
  {#if error}<p class="bad">{error}</p>{/if}

  {#each jobs.filter((j) => j.status === 'running' || j.status === 'queued' || j.status === 'failed').slice(0, 4) as j}
    <div class="job">
      <b>{j.name}</b>
      {#if j.status === 'running'}
        díl {j.progress?.part || 1}/{j.progress?.parts || j.parts} {j.progress?.name || ''}
        <progress max="100" value={pct(j)}></progress> {pct(j)} % · {clock(j.progress?.elapsed)}
        <button onclick={() => cancel(j.id)}>Zrušit</button>
      {:else if j.status === 'queued'}
        čeká ve frontě <button onclick={() => cancel(j.id)}>Zrušit</button>
      {:else}
        <span class="bad">selhalo: {j.error}</span>
      {/if}
    </div>
  {/each}

  <div class="outputs">
    {#each outputs as set}
      <div class="set">
        <div class="set-name">{set.name}</div>
        {#each set.files as f}
          <div class="file">
            <button class="mini" onclick={() => (playing = playing === f.url ? '' : f.url)}>{playing === f.url ? '■' : '▶'}</button>
            <span class="fname">{f.name}</span>
            <span class="dim">{f.seconds ? clock(f.seconds) + ' · ' : ''}{mb(f.bytes)}</span>
            <button class="mini" onclick={() => reveal(set.name, f.name)}>Ve Finderu</button>
          </div>
          {#if playing === f.url}
            <!-- svelte-ignore a11y_media_has_caption -->
            <video src={f.url} controls autoplay class="player"></video>
          {/if}
        {/each}
      </div>
    {:else}
      <p class="hint">Hotová videa se objeví tady. Do telefonu AirDropem z Finderu.</p>
    {/each}
  </div>
</section>
