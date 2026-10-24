The public website uses the supplied MindFriend home, privacy and terms pages, plus support and accessibility destinations used by the app. The existing app Support address is `support@mindfriend.app`.

Run `sh landing-page/build-css.sh` from the repository root to rebuild the two stylesheets with the existing Tailwind 3 themes. The build uses Tailwind CSS 3.4.17; no JavaScript is required to display page content. The optional animation libraries retain their original CDN integrity pins.

Run `python3 landing-page/deploy/package.py OUTPUT.tar.gz` to create a public-only archive and SHA-256 manifest. The ten-file allowlist excludes old auth experiments, workflow JSON, build inputs and private files. The app screenshot is an existing public App Store asset; its source is recorded in `assets/sources.json`. Tailwind's license is included.

The production configuration serves `getmindfriend.app` from `/srv/mindfriend-site/current` and redirects `www` to the apex while preserving the URI. Caddy obtains and renews free HTTPS certificates. The dedicated `mindfriend-site.service` runs as the existing `www-data` account with its TLS state under `/var/lib/mindfriend-site`; the Caddy admin endpoint is disabled. No app/backend credentials belong in this website.

Production activation requires explicit approval. Validate the Caddyfile, inspect existing listeners and paths, verify the public archive manifest and pinned Caddy release checksum, and preserve the current release before changing the `current` symlink. Do not replace an unrelated web service, modify DNS/firewalls or upgrade the VPS plan as part of this deployment.

For a first installation, rollback stops and disables only `mindfriend-site.service`, restoring the original absence of a website listener. Keep its release files and private TLS state recoverable. For later updates, restore the previous `current` target and restart only this service. Verify HTTP/HTTPS, apex/www, legal/support/accessibility routes, unknown-path 404, and mobile rendering after activation.
