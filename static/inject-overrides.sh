#!/bin/bash
# Inject overrides.js into Paperless-ngx frontend
# Runs at container startup before the main entrypoint

TEMPLATE="/usr/src/paperless/src/documents/templates/index.html"
MARKER="overrides.js"

# Copy overrides.js to the static directory (served publicly by WhiteNoise)
if [ -f /custom-init/overrides.js ]; then
    cp /custom-init/overrides.js /usr/src/paperless/static/overrides.js
    echo "Copied overrides.js to static directory"
fi

# Inject script tag into the template
if [ -f "$TEMPLATE" ] && ! grep -q "$MARKER" "$TEMPLATE"; then
    sed -i 's|</body>|<script src="/static/overrides.js" defer></script>\n</body>|' "$TEMPLATE"
    echo "Injected overrides.js into frontend template"
fi

# Execute the original s6-overlay entrypoint
exec /init "$@"
