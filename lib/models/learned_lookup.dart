import '../generated/learned.dart';
import 'image_model.dart';
import 'learned.dart';

export '../generated/learned.dart';
export 'learned.dart';

/// Jediné místo, kde se overlay čte.
///
/// Ne `kLearned.xxx ?? …` rozseté po kódu: fallback je invariant („nikdy horší
/// než dnes"), a invariant rozsypaný na šest míst se na sedmém poruší. Každá
/// funkce tady vrací **dnešní zadrátovanou hodnotu**, dokud se nenaměří něco
/// lepšího.
///
/// `overlay` je parametr, ne globál sebraný uvnitř: jinak by se invariant dal
/// testovat jen tak, jak zrovna vypadá commitnutý `learned.dart`, a první
/// opravdové spuštění generátoru by testy shodilo. Takhle je I1 vlastnost
/// kódu, ne dat.

/// Síla LoRA pro daný soubor. Bez naměřené hodnoty výchozí
/// [kDefaultLoraStrength], tedy to, co appka dělala dřív.
double loraStrengthFor(String? loraName, {Learned overlay = kLearned}) =>
    overlay.loraStrength[loraName]?.value ?? kDefaultLoraStrength;

/// Proč zrovna tahle síla — pro tooltip u odznaku „naučeno". Null = nenaučeno.
String? loraStrengthReason(String? loraName, {Learned overlay = kLearned}) =>
    overlay.loraStrength[loraName]?.reason;

/// Výchozí model pro daný záměr. Bez rozhodnutí [kDefaultImageModelId].
///
/// Klíč přítomný s hodnotou `null` znamená „měřeno, nerozhodnuto" — pro
/// volajícího je to totéž co nenaučeno, ale generovaný soubor u toho nese
/// důvod, takže při review jde rozlišit „ještě málo dat" od „nikdo neměřil".
String defaultModelFor(GenIntent intent, {Learned overlay = kLearned}) =>
    overlay.defaultModel[intent]?.value ?? kDefaultImageModelId;

String? defaultModelReason(GenIntent intent, {Learned overlay = kLearned}) =>
    overlay.defaultModel[intent]?.reason;

/// Co se naměřilo o modelu. Null = nic; picker pak ukáže
/// [ImageModelSpec.styleNote] jako dřív.
LearnedModel? learnedModelFor(String modelId, {Learned overlay = kLearned}) =>
    overlay.models[modelId];

/// Příznak stylu na konkrétním modelu, nebo null. **Nikdy neskrývá** — volající
/// z toho dělá ikonu a tooltip, ne filtr.
StyleFlag? styleFlagFor(String modelId, String styleId,
        {Learned overlay = kLearned}) =>
    overlay.styleFlags[modelId]?[styleId];
