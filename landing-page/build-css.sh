#!/bin/sh
set -eu
cd "$(dirname "$0")"
npm exec --yes --package=tailwindcss@3.4.17 -- tailwindcss -c style-source/home.config.cjs -i style-source/input.css --content index.html -o css/home.css --minify
npm exec --yes --package=tailwindcss@3.4.17 -- tailwindcss -c style-source/legal.config.cjs -i style-source/input.css --content 'privacy/index.html,terms/index.html,support/index.html,accessibility/index.html' -o css/legal.css --minify
