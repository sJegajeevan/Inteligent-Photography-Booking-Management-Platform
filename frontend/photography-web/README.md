# React + Vite

## Studio Profile map picker

The existing profile editor uses `@vis.gl/react-google-maps` for optional map
selection. Choose **Choose location on map**, then click to update Latitude and
Longitude (six decimal places). Only **Save profile** persists the fields through
the existing authenticated profile API. Existing coordinates show a marker;
empty coordinates show a Sri Lanka overview with no marker and no form changes.
Manual coordinates remain available and keep the existing pair/range validation.
No geocoding or device/customer GPS is used.

To enable the picker:

1. Enable billing and **Maps JavaScript API** in your Google Cloud project.
2. Create a browser API key restricted to Maps JavaScript API and your approved
   website HTTP referrers (include the local development origin when needed).
3. Set `VITE_GOOGLE_MAPS_API_KEY` in an ignored `.env.local` file or deployment
   build environment. The empty setting is documented in `.env.example`.
4. Restart Vite, or rebuild/redeploy for production. Browser keys are visible
   in client bundles; apply the Google Cloud restrictions above.

See [Google's setup instructions](https://developers.google.com/maps/documentation/javascript/get-api-key).
No backend key, Places API, Geocoding API or map ID is required for this picker.
The package's standard Marker component is used without a cloud map style.

Without a key, a small message replaces the map. Script/network failure,
authentication failure or a 20-second script-load timeout also leave manual
entry and saving available. After fixing a key/configuration failure, reload
the page. Live map selection requires manual verification with a configured
key: existing/empty coordinates, clicking, manual edits, cancel versus save,
and mobile viewport layout. Build and lint checks do not validate a live key.

This template provides a minimal setup to get React working in Vite with HMR and some ESLint rules.

Currently, two official plugins are available:

- [@vitejs/plugin-react](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react) uses [Oxc](https://oxc.rs)
- [@vitejs/plugin-react-swc](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react-swc) uses [SWC](https://swc.rs/)

## React Compiler

The React Compiler is not enabled on this template because of its impact on dev & build performances. To add it, see [this documentation](https://react.dev/learn/react-compiler/installation).

## Expanding the ESLint configuration

If you are developing a production application, we recommend using TypeScript with type-aware lint rules enabled. Check out the [TS template](https://github.com/vitejs/vite/tree/main/packages/create-vite/template-react-ts) for information on how to integrate TypeScript and [`typescript-eslint`](https://typescript-eslint.io) in your project.
