# Rendered on every start with the server's allocation port in place of
# __PORT__. Nothing here may write outside /tmp or /home/container.

worker_processes 2;
pid /tmp/ventacart/nginx.pid;
error_log stderr warn;

events {
    worker_connections 512;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log off;
    server_tokens off;
    sendfile on;
    tcp_nopush on;
    keepalive_timeout 65;

    # Room for product photo batches. Request bodies are buffered on disk,
    # not in the small /tmp Wings gives the container.
    client_max_body_size 64m;
    client_body_temp_path /home/container/.runtime/nginx/body;
    fastcgi_temp_path     /home/container/.runtime/nginx/fastcgi;
    proxy_temp_path       /tmp/ventacart/nginx-proxy;
    uwsgi_temp_path       /tmp/ventacart/nginx-uwsgi;
    scgi_temp_path        /tmp/ventacart/nginx-scgi;

    # The port the browser asked for, when it asked for one. Debian's
    # fastcgi_params hands PHP the host alone, with the port removed, so a
    # store reached at node:2466 would build every link to node:80 instead.
    map $http_host $client_port {
        "~:(?<p>[0-9]+)$" ":$p";
        default           "";
    }

    gzip on;
    gzip_types text/css application/javascript application/json image/svg+xml;

    server {
        listen __PORT__ default_server;
        server_name _;
        root /home/container/public;
        index index.php;
        charset utf-8;

        location / {
            try_files $uri $uri/ /index.php?$query_string;
        }

        # Vite names every built file after its contents, so a file under
        # /build/ never changes and can be kept for a year.
        location ^~ /build/ {
            expires 1y;
            add_header Cache-Control "public, immutable";
            try_files $uri =404;
        }

        # Product photos and uploads, served straight from storage/app/public.
        location ^~ /storage/ {
            expires 7d;
            add_header Cache-Control "public";
            try_files $uri =404;
        }

        location = /favicon.ico { access_log off; log_not_found off; }
        location = /robots.txt  { access_log off; log_not_found off; try_files $uri /index.php?$query_string; }

        location ~* \.(?:css|js|png|jpe?g|gif|svg|webp|ico|woff2?)$ {
            expires 7d;
            try_files $uri /index.php?$query_string;
        }

        location ~ \.php$ {
            fastcgi_pass unix:/tmp/ventacart/php-fpm.sock;
            fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
            fastcgi_param DOCUMENT_ROOT $realpath_root;
            include /etc/nginx/fastcgi_params;
            # After the include, so PHP takes this one over Debian's.
            fastcgi_param HTTP_HOST $host$client_port;
            fastcgi_read_timeout 300;
            fastcgi_buffer_size 32k;
            fastcgi_buffers 16 16k;
        }

        location ~ /\.(?!well-known).* {
            deny all;
        }
    }
}
