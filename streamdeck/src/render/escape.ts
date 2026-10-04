/**
 * Escapes text that goes into an SVG document.
 *
 * Labels come from the translation files; a stray ampersand there must not be able to
 * break the key image.
 * @param text Text to escape.
 * @returns The escaped text.
 */
export function escapeText(text: string): string {
	return text.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

/**
 * Escapes a value that goes into an attribute, where a quote would end it early.
 * @param value Value to escape.
 * @returns The escaped value.
 */
export function escapeAttribute(value: string): string {
	return escapeText(value).replaceAll('"', "&quot;");
}
