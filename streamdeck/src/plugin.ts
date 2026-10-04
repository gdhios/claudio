/**
 * Wires the plugin together: one bridge to Claudio, one store the keys draw from.
 */

import streamDeck from "@elgato/streamdeck";

import { ClaudioActionKey } from "./actions/action.js";
import { ClaudioKey } from "./actions/claudio.js";
import { DictateKey } from "./actions/dictate.js";
import { FaceKey } from "./actions/face-tile.js";
import type { KeyDependencies } from "./actions/keys.js";
import { NavigateKey } from "./actions/navigate.js";
import { WindowKey } from "./actions/window.js";
import { BridgeClient } from "./bridge/client.js";
import { IdleReturn } from "./idle.js";
import { CLAUDIO_BUNDLE_ID, tryOpenClaudio } from "./launch.js";
import { followBridge } from "./state/follow.js";
import { Store } from "./state/store.js";

const store = new Store();
const bridge = new BridgeClient({
	pluginVersion: streamDeck.info.plugin.version,
	logger: streamDeck.logger,
});

followBridge(bridge, store);

// Where each deck stands in the Claudio profile, and when it goes back to the face.
const idle = new IdleReturn((deviceId, profile, page) => streamDeck.profiles.switchToProfile(deviceId, profile, page));

const dependencies: KeyDependencies = {
	bridge,
	store,
	openClaudio: tryOpenClaudio,
	translate: (key) => streamDeck.i18n.translate(key),
	touch: (deviceId) => idle.touch(deviceId),
};

streamDeck.actions.registerAction(new ClaudioActionKey(dependencies));
streamDeck.actions.registerAction(new WindowKey(dependencies));
streamDeck.actions.registerAction(
	new ClaudioKey({ ...dependencies, installProfile: (deviceId) => idle.show(deviceId, "face") }),
);
streamDeck.actions.registerAction(
	// Only the Dictate key and the face follow the microphone level, so only they listen.
	new DictateKey({ ...dependencies, onLevel: (listener) => bridge.on("level", listener) }),
);
streamDeck.actions.registerAction(
	new FaceKey({
		...dependencies,
		onLevel: (listener) => bridge.on("level", listener),
		showActions: (deviceId) => idle.show(deviceId, "actions"),
		sawFace: (deviceId) => idle.sawFace(deviceId),
		setIdleSeconds: (seconds) => idle.setDelay(seconds),
	}),
);
streamDeck.actions.registerAction(
	new NavigateKey({
		store,
		translate: dependencies.translate,
		touch: dependencies.touch,
		show: (deviceId, page) => idle.show(deviceId, page),
		leave: (deviceId) => idle.leave(deviceId),
	}),
);

// Stream Deck watches the application listed in the manifest, so the bridge can stop
// dialling an app that is not there.
streamDeck.system.onApplicationDidLaunch((ev) => {
	if (ev.application === CLAUDIO_BUNDLE_ID) {
		store.setClaudioRunning(true);
		bridge.setClaudioRunning(true);
	}
});

streamDeck.system.onApplicationDidTerminate((ev) => {
	if (ev.application === CLAUDIO_BUNDLE_ID) {
		store.setClaudioRunning(false);
		bridge.setClaudioRunning(false);
	}
});

await streamDeck.connect();
bridge.start();
