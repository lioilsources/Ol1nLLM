/// Typy pro `lib/generated/learned.dart` — overlay toho, co se mezi releasy
/// naměřilo ve FINETUNE gallery.
///
/// Učení se děje **při buildu, ne za běhu**: `lab learn` stáhne eval, rozhodne
/// (čistá funkce v `tools/lab/decide.go`) a vygeneruje Dart, který jde přes
/// git review jako každá jiná změna chování. Appka pak čte konstanty, ne síť —
/// offline funguje, release je diffovatelný snapshot a „auto-selection must
/// never be silent" platí konstrukcí.
///
/// Čtyři pravidla, na kterých ty typy stojí:
///
/// **Overlay nikdy nenahrazuje, jen přebíjí.** Prázdný [Learned] musí dát
/// chování bit-identické s dneškem — proto má každé pole výchozí prázdnou
/// hodnotu a čte se přes `?? <dnešní konstanta>` v `learned_lookup.dart`.
///
/// **Nerozhodnutí je taky výstup.** Když pravidlo neprojde guardem, generátor
/// nevynechá klíč, ale emituje `null` s komentářem proč. Soubor tak dokumentuje
/// vlastní nejistotu; to je to, co při review řekne „hodnoť víc".
///
/// **Každá hodnota nese proveniences.** [LearnedValue.reason] je povinný a
/// neprázdný. Bez něj je „naučeno" jen jiné slovo pro „někdo to změnil".
///
/// **Registry zůstávají ruční.** Tenhle soubor nikdy nepřepisuje
/// `kImageModels` ani `kStylePresets` — id se persistují na uzlech a exportují
/// do galerie, takže jedno špatné spuštění generátoru by rozvázalo stará
/// hodnocení od obrázků.
library;

/// Co se od modelu žádá. Odvozuje se z toho, co provider už rozlišuje
/// (`isRepose`, `sourceImageId`) — ne nová persistovaná dimenze.
enum GenIntent {
  /// Generování z textu, bez předlohy.
  txt2img,

  /// Úprava předlohy (včetně inpaintu — ten má vlastní pravidla, ale z
  /// pohledu „který model" je to pořád práce nad zdrojovým obrázkem).
  img2img,

  /// „Zachovej pózu" — nový render, jehož póza je připnutá k referenci.
  repose,
}

/// Naměřený podíl s Wilsonovým 95% intervalem.
///
/// [lower] je to, podle čeho se řadí a rozhoduje: 3/3 nesmí přeskočit 40/45.
/// [upper] nese UI, aby šlo napsat „11–52 %" místo holého průměru, který o
/// patnácti vzorcích tvrdí totéž co o patnácti stech.
class Rate {
  const Rate(this.value, {
    required this.lower,
    required this.upper,
    required this.n,
  });

  /// Pozorovaný podíl (up / rated).
  final double value;

  /// Dolní a horní mez Wilsonova 95% intervalu.
  final double lower;
  final double upper;

  /// Kolik hodnocení za tím stojí.
  final int n;

  /// „62 %"
  String get percent => '${(value * 100).round()} %';

  /// „36–86 %" — rozpětí, ne bod.
  String get range =>
      '${(lower * 100).round()}–${(upper * 100).round()} %';
}

/// Co se ví o jednom modelu. Bez guardu a bez rozhodnutí — jen přepis buněk
/// evalu; `n` si UI ukáže samo a čtenář posoudí.
class LearnedModel {
  const LearnedModel({
    this.poseAdherence,
    this.sourceIdentity,
    this.sourceStyle,
    this.likeRate,
  });

  /// Relační kritéria: jak model drží pózu / identitu / styl **předlohy**.
  /// Null = na tohle kritérium nemá dost hodnocení (nebo žádná).
  final Rate? poseAdherence;
  final Rate? sourceIdentity;
  final Rate? sourceStyle;

  /// Prostý like. Vkus, ne fakt — proto se z něj nikdy nerozhoduje nic
  /// relačního (od toho jsou kritéria výš).
  final Rate? likeRate;

  bool get isEmpty =>
      poseAdherence == null &&
      sourceIdentity == null &&
      sourceStyle == null &&
      likeRate == null;

  /// Jedna řádka do pickeru: „póza 90 % (n=31) · identita 62 % (n=13)".
  ///
  /// **Vzorek se veze s číslem, ne vedle něj.** Průměr bez n tvrdí o třinácti
  /// hodnoceních totéž co o třinácti stech, a to je přesně ta záměna, kvůli
  /// které se celý harness stavěl.
  ///
  /// Null, když se nezměřilo nic — volající pak ukáže
  /// [ImageModelSpec.styleNote] jako dřív.
  String? get summary {
    final parts = <String>[
      if (poseAdherence != null) 'póza ${_cell(poseAdherence!)}',
      if (sourceIdentity != null) 'identita ${_cell(sourceIdentity!)}',
      if (sourceStyle != null) 'styl ${_cell(sourceStyle!)}',
      if (likeRate != null) 'like ${_cell(likeRate!)}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _cell(Rate r) => '${r.percent} (n=${r.n})';
}

/// Naučená hodnota i s tím, proč jí věřit.
///
/// [reason] je povinný a drží ho test — hodnota bez proveniences je změna
/// chování, kterou při review nejde posoudit.
class LearnedValue<T> {
  const LearnedValue(this.value, {required this.reason});

  final T value;

  /// Věta, ze které jde napsat release note: „dolní mez 0.71 > horní 0.58
  /// druhého ramene, n=22/19".
  final String reason;
}

/// Naučená volba mezi kandidáty (model pro daný [GenIntent]). Jen jiné
/// jméno pro [LearnedValue] nad id — aby generovaný soubor četl jako věta.
typedef LearnedChoice = LearnedValue<String>;

/// Jak se styl chová na konkrétním modelu.
///
/// **Nikdy neskrývá, jen označí.** Skrytý styl už nikdy nedostane další
/// hodnocení a nemůže se vrátit — samopotvrzující smyčka, ve které vítěz
/// vyhrál proto, že dostal víc příležitostí.
enum StyleVerdict { weak, strong }

class StyleFlag {
  const StyleFlag(this.verdict, {required this.reason});

  /// Horní mez pod prahem — styl na tomhle modelu prokazatelně nesedí.
  const StyleFlag.weak({required String reason})
      : this(StyleVerdict.weak, reason: reason);

  /// Dolní mez nad prahem — jen informace do pickeru, ne doporučení.
  const StyleFlag.strong({required String reason})
      : this(StyleVerdict.strong, reason: reason);

  final StyleVerdict verdict;
  final String reason;

  bool get isWeak => verdict == StyleVerdict.weak;
  bool get isStrong => verdict == StyleVerdict.strong;
}

/// Celý overlay. Prázdná instance je platný a očekávaný stav — appka se
/// tehdy chová přesně jako před zavedením učení.
class Learned {
  const Learned({
    this.snapshotAt,
    this.ratedImages = 0,
    this.totalImages = 0,
    this.minRatings = 0,
    this.models = const {},
    this.loraStrength = const {},
    this.defaultModel = const {},
    this.styleFlags = const {},
  });

  /// Kdy se eval četl (ISO 8601 UTC). Null = generátor ještě neběžel.
  final String? snapshotAt;

  /// Kolik obrázků v galerii mělo v okamžiku snapshotu hodnocení, a kolik
  /// jich tam bylo celkem. Ta dvojice je jediné číslo, ze kterého jde poznat,
  /// jestli „ještě nevím" znamená málo dat, nebo málo hodnocení.
  final int ratedImages;
  final int totalImages;

  /// Práh vzorku, se kterým generátor rozhodoval (`lab learn --min`).
  final int minRatings;

  /// Per-model naměřená kritéria. Klíč je [ImageModelSpec.id].
  final Map<String, LearnedModel> models;

  /// Síla LoRA podle jména souboru, jak ho hlásí ComfyUI.
  final Map<String, LearnedValue<double>> loraStrength;

  /// Výchozí model pro daný záměr. Hodnota `null` u klíče znamená „měřeno,
  /// nerozhodnuto" — v generovaném souboru s komentářem proč.
  final Map<GenIntent, LearnedChoice?> defaultModel;

  /// modelId → styleId → příznak.
  final Map<String, Map<String, StyleFlag>> styleFlags;

  /// True, dokud generátor neběžel. Pak platí dnešní zadrátované konstanty.
  bool get isEmpty => snapshotAt == null;

  DateTime? get snapshotTime =>
      snapshotAt == null ? null : DateTime.tryParse(snapshotAt!);

  /// Jak je znalost stará. Null, když snapshot chybí nebo je nečitelný.
  Duration? ageAt(DateTime now) {
    final t = snapshotTime;
    return t == null ? null : now.difference(t);
  }

  /// Stárnoucí snapshot je jediný způsob, jak si všimnout, že někdo releasoval
  /// bez `lab learn`. Prahu 30 dní odpovídá varování v `make build-*`.
  static const staleAfter = Duration(days: 30);

  bool isStaleAt(DateTime now) {
    final a = ageAt(now);
    return a != null && a > staleAfter;
  }
}
