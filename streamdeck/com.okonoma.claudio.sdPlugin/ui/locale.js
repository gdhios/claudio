/*
 * Strings for the property inspectors.
 *
 * The inspectors run in a browser, where sdpi-components resolves `__MSG_a.b.c__`
 * against this object alone — it never reads the plugin's own `fr.json` / `en.json`,
 * which only the plugin process can. So the key labels appear twice, once for each side,
 * under the same key paths: change one, change the other.
 */
SDPIComponents.i18n.locales = {
	fr: {
		inspector: {
			action: "Action",
			layout: "Disposition",
			language: "Langue",
			output: "Sortie",
			secondary: "La langue secondaire est la deuxième langue réglée dans la dictée de Claudio.",
			idleSeconds: "Retour au visage",
			profile: "Profil Claudio",
			installProfile: "Installer le profil Claudio",
			installProfileHint:
				"Le profil Claudio — visage, actions, fenêtres — ne peut être installé que par le plugin lui-même : un profil importé à la main ne change pas de page. Ce bouton l'installe sur ce deck, ou y retourne s'il existe déjà.",
		},
		idleSeconds: {
			30: { label: "30 s" },
			60: { label: "1 min" },
			120: { label: "2 min" },
			0: { label: "Jamais" },
		},
		dictate: {
			cleanup: { label: "Dicter" },
			translateEN: { label: "Dicter → EN" },
			makePrompt: { label: "Dicter → Prompt" },
		},
		language: {
			primary: { label: "Principale" },
			secondary: { label: "Secondaire" },
		},
		action: {
			correct: { label: "Corriger" },
			translateFR: { label: "Traduire (FR)" },
			translateEN: { label: "Traduire (EN)" },
			professionalTone: { label: "Ton pro" },
			summarize: { label: "Résumer" },
			makePrompt: { label: "Prompt" },
			expertPrompt: { label: "Prompt expert" },
			simplify: { label: "Lapacompris" },
			free: { label: "Action libre" },
			palette: { label: "Palette" },
			whatsPlaying: { label: "J'écoute quoi ?" },
		},
		window: {
			leftHalf: { label: "Moitié gauche" },
			rightHalf: { label: "Moitié droite" },
			topHalf: { label: "Moitié haute" },
			bottomHalf: { label: "Moitié basse" },
			topLeft: { label: "Quart haut gauche" },
			topRight: { label: "Quart haut droit" },
			bottomLeft: { label: "Quart bas gauche" },
			bottomRight: { label: "Quart bas droit" },
			maximize: { label: "Plein écran" },
			center: { label: "Centrer" },
			nextScreen: { label: "Écran suivant" },
		},
	},
	en: {
		inspector: {
			action: "Action",
			layout: "Layout",
			language: "Language",
			output: "Output",
			secondary: "The secondary language is the second one set in Claudio's dictation settings.",
			idleSeconds: "Return to the face",
		},
		idleSeconds: {
			30: { label: "30 s" },
			60: { label: "1 min" },
			120: { label: "2 min" },
			0: { label: "Never" },
		},
		dictate: {
			cleanup: { label: "Dictate" },
			translateEN: { label: "Dictate → EN" },
			makePrompt: { label: "Dictate → Prompt" },
		},
		language: {
			primary: { label: "Primary" },
			secondary: { label: "Secondary" },
		},
		action: {
			correct: { label: "Correct" },
			translateFR: { label: "Translate (FR)" },
			translateEN: { label: "Translate (EN)" },
			professionalTone: { label: "Professional tone" },
			summarize: { label: "Summarize" },
			makePrompt: { label: "Prompt" },
			expertPrompt: { label: "Expert prompt" },
			simplify: { label: "Explain simply" },
			free: { label: "Free action" },
			palette: { label: "Palette" },
			whatsPlaying: { label: "What's playing?" },
		},
		window: {
			leftHalf: { label: "Left half" },
			rightHalf: { label: "Right half" },
			topHalf: { label: "Top half" },
			bottomHalf: { label: "Bottom half" },
			topLeft: { label: "Top left" },
			topRight: { label: "Top right" },
			bottomLeft: { label: "Bottom left" },
			bottomRight: { label: "Bottom right" },
			maximize: { label: "Full screen" },
			center: { label: "Centre" },
			nextScreen: { label: "Next screen" },
		},
	},
};
