#!/bin/bash

set -e

# Simple config like local
create_simple_config() {
  local config="/opt/config/config.json"
  
  echo "Creating simple config like local..."
  
  cat > "$config" << CONFIG_EOF
{
    "url": "${SITE_URL:-https://forum.codeproject.com}",
    "secret": "${NODEBB_SECRET:-super-strong-secret-key-for-production-change-this}",
    "database": "mongo",
    "mongo": {
        "host": "$NODEBB_DB_HOST",
        "port": ${NODEBB_DB_PORT:-27017},
        "database": "$NODEBB_DB_NAME",
        "username": "$NODEBB_DB_USER", 
        "password": "$NODEBB_DB_PASSWORD",
        "options": {
            "authSource": "${NODEBB_DB_AUTH_SOURCE:-admin}",
            "ssl": ${NODEBB_DB_SSL:-true},
            "tlsInsecure": true,
            "retryWrites": false,
            "readPreference": "primary",
            "maxPoolSize": 10,
            "minPoolSize": 2
        }
    },
    "port": ${PORT:-4567},
    "bind_address": "0.0.0.0",
    "upload_path": "/usr/src/app/public/uploads",
    "sessionStore": {
        "name": "database"
    },
    "cluster": {
        "port": ${PORT:-4567}
    }
}
CONFIG_EOF

  echo "✓ Simple config created"
  cp "$config" /usr/src/app/config.json
  echo "✓ Copied to /usr/src/app/config.json"
}

# Create directories
mkdir -p /opt/config
mkdir -p public/uploads
mkdir -p logs

echo "DEBUG: Running as user: $(whoami)"
echo "DEBUG: Working directory: $(pwd)"

# Create simple config
create_simple_config

# Just like local: build then start
echo "🔧 Installing default theme and plugins first..."
npm install nodebb-theme-harmony nodebb-plugin-composer-default nodebb-plugin-markdown nodebb-widget-essentials || true

echo "🎨 Activating theme and essential plugins..."
node ./nodebb activate nodebb-theme-harmony || true
node ./nodebb activate nodebb-plugin-composer-default || true 
node ./nodebb activate nodebb-plugin-markdown || true
node ./nodebb activate nodebb-widget-essentials || true

echo "🔨 Building NodeBB with forced asset generation..."
node ./nodebb build

echo "🔧 Verifying critical files exist..."
# Check if critical files were created
if [ ! -f "build/public/nodebb.min.js" ]; then
    echo "⚠️ nodebb.min.js missing - rebuilding client bundle..."
    node ./nodebb build client
fi

if [ ! -f "build/public/admin.min.js" ]; then
    echo "⚠️ admin.min.js missing - rebuilding admin bundle..."
    node ./nodebb build admin
fi

# Create favicon if missing
if [ ! -f "public/uploads/system/favicon.ico" ]; then
    echo "🎯 Creating missing favicon..."
    mkdir -p public/uploads/system
    # Use NodeBB's default favicon or create a simple one
    cp public/favicon.ico public/uploads/system/favicon.ico 2>/dev/null || 
    echo "Creating placeholder favicon..." > public/uploads/system/favicon.ico
fi

echo "✅ Asset verification completed"

echo "🔧 Fixing admin panel jQuery issue..."
# Fix admin.min.js to include jQuery
if [ -f "build/public/admin.min.js" ]; then
    echo "Adding jQuery polyfill to admin.min.js..."
    # Create a simple jQuery polyfill and prepend to admin.min.js
    cat > /tmp/jquery-polyfill.js << 'JQUERY_EOF'
// Minimal jQuery polyfill for NodeBB admin panel
(function(window) {
  if (typeof window.$ === 'undefined') {
    var $ = function(selector) {
      if (typeof selector === 'function') {
        if (document.readyState === 'loading') {
          document.addEventListener('DOMContentLoaded', selector);
        } else {
          selector();
        }
        return;
      }
      return document.querySelectorAll(selector);
    };
    
    $.fn = {};
    $.extend = function(target, source) {
      for (var key in source) {
        if (source.hasOwnProperty(key)) {
          target[key] = source[key];
        }
      }
      return target;
    };
    
    $.ajax = function(options) {
      var xhr = new XMLHttpRequest();
      xhr.open(options.type || 'GET', options.url);
      if (options.success) xhr.onload = function() { options.success(xhr.responseText); };
      if (options.error) xhr.onerror = options.error;
      xhr.send(options.data);
    };
    
    $.ready = function(fn) { $(fn); };
    $.noop = function() {};
    
    window.$ = window.jQuery = $;
    console.log('jQuery polyfill loaded for admin panel');
  }
})(window);
JQUERY_EOF
    
    # Prepend polyfill to admin.min.js
    cat /tmp/jquery-polyfill.js build/public/admin.min.js > /tmp/admin-with-jquery.min.js
    mv /tmp/admin-with-jquery.min.js build/public/admin.min.js
    echo "✅ jQuery polyfill added to admin.min.js"
fi

echo "🚀 Starting NodeBB directly (AWS ECS compatible)..." 
exec node app.js