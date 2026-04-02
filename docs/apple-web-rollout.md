# Apple Web Rollout

Current repo state:

- `Sign in with Apple` already exists in the website auth flow.
- `Apple Pay` is represented in pricing and the backend already has Stripe checkout infrastructure.
- `MapKit JS`, `WeatherKit`, `CloudKit JS`, `MusicKit`, `Apple Wallet passes`, and `Safari Web Push` were not previously surfaced as a website rollout layer.

What was added:

- `/website/apple-ecosystem.html`
- `/website/apple-ecosystem.js`
- `/website/apple-web-config.js`
- `/website/apple-web-sw.js`

What still needs to happen on your end for real-world functionality:

1. Sign in with Apple
Set or confirm a Services ID, web redirect URI, and production domain association in Apple Developer.

2. Apple Pay on the Web
Verify the production domain in Stripe for Apple Pay and ensure the billing env vars are set on the backend.

3. MapKit JS
Create a MapKit JS key/token and place the signed token in `window.ATLAS_APPLE_WEB_CONFIG.mapkitToken`.

4. WeatherKit
Create a WeatherKit key and expose a signed backend endpoint.
Set its public URL in `window.ATLAS_APPLE_WEB_CONFIG.weatherkitEndpoint`.

5. CloudKit JS
Choose a CloudKit container and record schema, then set `cloudKitContainerId`.

6. MusicKit JS
Create a MusicKit developer token and set `musicKitDeveloperToken`.

7. Apple Wallet passes
Create a Pass Type ID and pass-signing certificate.
Expose a backend endpoint that returns real `.pkpass` files and set `walletPassBaseUrl`.

8. Safari Web Push
Set a real push public key and subscribe endpoint in `pushPublicKey` and `pushSubscribeEndpoint`.
Keep the service worker file deployed at `/apple-web-sw.js`.
