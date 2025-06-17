set -e

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
            "tlsInsecure": true
        }
    },
    "port": 4567,
    "bind_address": "0.0.0.0"
}
EOF

cp /opt/config/config.json /usr/src/app/config.json

npm install nodebb-plugin-composer-default nodebb-theme-harmony
./nodebb activate nodebb-plugin-composer-default
./nodebb activate nodebb-theme-harmony
./nodebb activate nodebb-plugin-markdown  
./nodebb activate nodebb-widget-essentials


while true; do
    node ./nodebb build
    echo "Starting NodeBB..."
    node app.js
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo "NodeBB requested restart, restarting in 2 seconds..."
        sleep 2
    else
        echo "NodeBB crashed with exit code $EXIT_CODE, exiting container"
        exit $EXIT_CODE
    fi
done