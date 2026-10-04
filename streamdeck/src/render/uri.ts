/**
 * How a drawing travels to the Stream Deck app.
 *
 * The app only accepts an image as a data URI — a bare SVG string is silently ignored,
 * and the key keeps whatever static image its manifest gave it. Base64 carries the
 * drawing rather than a URI-escaped string, so nothing inside it — accents, `#`, `<`,
 * `"` — needs escaping a second time.
 */

/** The prefix every drawing is wrapped in before it reaches `setImage`. */
export const SVG_DATA_URI_PREFIX = "data:image/svg+xml;base64,";

/**
 * Wraps an SVG document the way `setImage` expects it.
 * @param svg The drawing.
 * @returns The data URI.
 */
export function svgDataUri(svg: string): string {
	return `${SVG_DATA_URI_PREFIX}${Buffer.from(svg, "utf8").toString("base64")}`;
}
