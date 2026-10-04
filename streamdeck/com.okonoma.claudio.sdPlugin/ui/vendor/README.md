# Vendored, not written here

`sdpi-components.js` is **sdpi-components v4.0.1**, taken unmodified from
<https://sdpi-components.dev/releases/v4/sdpi-components.js>. Its licence notice is the
banner at the top of the file: Corsair Memory Inc. and other contributors, with Lit under
BSD-3-Clause.

It is a copy rather than a `<script src>` to the CDN because a property inspector with no
network would otherwise render none of its controls — the one place the user goes to
choose what a key does.

To take a newer release, replace the file with the one that release serves and keep its
banner; `tests/locales.test.ts` and a look at both inspectors are what say it still works.
