package main

// Copy is a Czech explanation plus where the claim comes from, so a reader can
// check it and a later editor knows what would invalidate it.
type Copy struct {
	Text   string `json:"text"`
	Source string `json:"source"`
}

var copyCS = map[string]Copy{
	"depth_vs_pose": {
		Text: "Hloubková mapa z předlohy (DepthAnything v2). Drží stanoviště, " +
			"proporce i směr pohledu — na rozdíl od kostry, která směr zahazuje " +
			"a čelní postavu umí otočit zády.",
		Source: "lib/services/comfyui_service.dart — komentář u setAutoPose",
	},
	"wired_pose": {
		Text: "Drátěná póza: hotový OpenPose skeleton na plnou sílu 1.0 přes celý " +
			"rozvrh. Na 0.9 a 0.8 prohrával s promptem, který naznačoval jinou pózu.",
		Source: "lib/services/comfyui_service.dart — _poseStrength",
	},
	"cn_strength": {
		Text: "u „zachovej pózu\" je výchozí 0.75 a konec na 90 %: při plné síle " +
			"přes celý rozvrh se zapeče objem těla z předlohy a pere se s novou postavou",
		Source: "lib/services/comfyui_service.dart — _reposeDepthStrength",
	},
	"denoise_high": {
		Text: "Vysoký denoise (0.9): teprve tady projde výtvarný styl a pózu dál " +
			"drží ControlNet. Při presetových ~0.72 je img2img stylově skoro slepý.",
		Source: "docs/style-matrix.md — rozptyl stylů 0.005–0.42 vs repose 0.42–0.71",
	},
	"denoise_preset": {
		Text: "Presetový denoise (~0.72): zdrojový latent nese pózu, ale i paletu " +
			"a světlo. Prompt přebarví sukni, výtvarný jazyk nepřepíše.",
		Source: "docs/style-matrix.md",
	},
	"depth_fit": {
		Text: "Předloha se před hloubkou i tváří letterboxuje na poměr latentu " +
			"(černé pruhy). Bez toho ji ControlNet škáluje na šířku a přebytek " +
			"ořízne shora a zdola — u fotky 1:2 v bucketu 768×1344 přišla o hlavu " +
			"i chodidla, a InstantID o klíčové body obličeje u horního okraje.",
		Source: "lib/services/comfyui_service.dart — _fitUpscaleMethod; " +
			"ComfyUI comfy/controlnet.py common_upscale(…, \"center\")",
	},
	"latent_bucket": {
		Text: "Latent se láme na nejbližší SDXL bucket podle poměru stran předlohy " +
			"— jinak by ControlNet hloubkovou mapu ořízl na střed a přišly by " +
			"o sebe končetiny.",
		Source: "lib/models/latent_bucket.dart",
	},
	"metrics": {
		Text: "Rozptyl a reakce měří barvu, ne převzetí stylu. Slouží k předvýběru; " +
			"rozhodnout musí pohled na obrázky.",
		Source: "docs/style-matrix.md — druhá vlna stylů",
	},
	"face_identity": {
		Text: "Tvář se čte z téže předlohy jako hloubková mapa — žádný druhý " +
			"upload. Drží přes celý rozvrh (na rozdíl od hloubky, která končí " +
			"na 90 %): obličej nemá do čeho dosedat, takže pustit ho dřív " +
			"znamená nechat prompt rysy zase odvést.",
		Source: "lib/services/comfyui_service.dart — _faceIdentityEndAt",
	},
	"face_detail": {
		Text: "Druhý průchod jen přes nalezený obličej, denoise 0.4 — opraví " +
			"rysy, ale nevymyslí jiného člověka. Podmínění bere zpřed hloubkového " +
			"ControlNetu: detailer pracuje s výřezem a celoobrazová hloubková " +
			"mapa natažená na výřez popisuje něco jiného.",
		Source: "lib/services/comfyui_service.dart — _injectFaceDetailer",
	},
	"face_provider": {
		Text: "InsightFace jede na CPU, stejně jako v odeslaném face inpaintu: " +
			"detektor je malý a nemusí uprostřed jobu soupeřit s difuzí o VRAM.",
		Source: "assets/comfyui/flux_fill_inpaint_face.api.json — uzel 85",
	},
	"preset_overridden": {
		Text: "Tahle buňka běžela s přebitým presetem, takže to není verdikt " +
			"o modelu — kalibrace (třeba 6 kroků u Lightningu) je pryč.",
		Source: "lib/models/image_model.dart — ComfyPreset",
	},
}
