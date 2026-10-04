/**
 * Writes the bundled Stream Deck profile to `destination` (the plugin's own copy when
 * omitted). See `make-profile.mjs` for what it writes.
 * @param destination Where to write the `.streamDeckProfile` file.
 */
export declare function writeProfile(destination?: string): Promise<void>;
