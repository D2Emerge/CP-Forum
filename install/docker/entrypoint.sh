set -e

create_config() {
    cat > /opt/config/config.json << EOF
{
    "url": "https://forum.codeproject.com",
    "secret": "super-strong-secret-key-for-production-change-this",
    "database": "mongo",
    "mongo": {
        "host": "$NODEBB_DB_HOST",
        "port": "$NODEBB_DB_PORT",
        "database": "$NODEBB_DB_NAME",
        "username": "$NODEBB_DB_USER",
        "password": "$NODEBB_DB_PASSWORD",
        "options": {
            "authSource": "admin",
            "retryWrites": false,
            "readPreference": "primary",
            "ssl": true,
            "tlsInsecure": true,
            "maxPoolSize": 10,
            "minPoolSize": 2
        }
    },
    "port": 4567,
    "bind_address": "0.0.0.0",
    "upload_path": "/var/lib/nodebb/uploads",
    "sessionStore": {
        "name": "database"
    }
}
EOF
    
    cp /opt/config/config.json /usr/src/app/config.json
    echo "✓ Config created"
}

setup_plugins() {
    echo "🔧 Installing essential plugins..."
    npm install nodebb-plugin-composer-default nodebb-theme-harmony
    
    echo "🎯 Activating plugins..."
    ./nodebb activate nodebb-plugin-composer-default
    ./nodebb activate nodebb-theme-harmony
    ./nodebb activate nodebb-plugin-markdown
    ./nodebb activate nodebb-widget-essentials
}

build_nodebb() {
    echo "🔨 Building NodeBB..."
    node ./nodebb build
    echo "✓ Build completed"
}

restart_wrapper() {
    while true; do
        echo "🚀 Starting NodeBB..."
        node app.js
        EXIT_CODE=$?
        echo "NodeBB exited with code: $EXIT_CODE"
        
        case $EXIT_CODE in
            0)
                echo "↻ Restart requested, restarting in 2 seconds..."
                sleep 2
                ;;
            200)
                echo "🔨 Build & Restart requested, rebuilding..."
                if node ./nodebb build; then
                    echo "✓ Rebuild completed"
                else
                    echo "⚠️ Build failed, continuing anyway"
                fi
                sleep 2
                ;;
            *)
                echo "💥 NodeBB crashed with exit code $EXIT_CODE"
                exit $EXIT_CODE
                ;;
        esac
    done
}

main() {
    echo "🏁 Starting NodeBB setup..."
    echo "Running as user: $(whoami)"
    echo "Working directory: $(pwd)"
    
    create_config
    setup_plugins  
    build_nodebb
    
    echo "🎉 Setup completed! Starting NodeBB with restart support..."
    restart_wrapper
}

main "$@"