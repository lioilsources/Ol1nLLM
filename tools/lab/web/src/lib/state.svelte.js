// The studio's state: the recipe being composed and what the server said
// about it. Components read and write `st` directly.

export function defaultRecipe() {
  return {
    version: 1,
    name: 'video',
    source: { runs: [] },
    select: {},
    frame: { tiles: '', cols: 0, fit: 'contain', title: 'none', captions: { mode: 'none' }, reference: false },
    time: { axes: [], loose: [], pair: 'order', complete: true, rate: 4, fade: 0.4 },
    output: { size: '1080x1920', fps: 30, per: [], crf: 18 },
  };
}

export const st = $state({
  index: null, // families, runs, templates, axisNames
  recipe: defaultRecipe(),
  coverage: null, // {coverage, axes, pictures, …}
  covRows: 'model',
  covCols: 'style',
  suggest: null,
  plan: null, // {id, storyboard, slides}
  planError: null, // {error, problems, missing}
  planning: false,
  notes: [],
  error: '',
  saved: [],
  outputs: [],
  jobs: [],
  yaml: '',
  yamlError: '',
  showYaml: false,
});

export const AXES = ['prompt', 'character', 'prefix', 'style', 'flow', 'variant', 'model'];

export function axisName(a) {
  return st.index?.axisNames?.[a] || a;
}

// A plain copy of the recipe for the API (no proxies, no empty bits).
export function recipeJSON() {
  const r = JSON.parse(JSON.stringify(st.recipe));
  for (const [k, v] of Object.entries(r.select || {})) {
    if (!v || (!(v.only || []).length && !(v.not || []).length && !(v.kind || []).length)) delete r.select[k];
  }
  if (!r.output.split || !r.output.split.seconds) delete r.output.split;
  if (!r.output.maxSeconds) delete r.output.maxSeconds;
  if (!r.time.loose?.length) r.time.pair = r.time.pair || 'order';
  return r;
}
