# renovate: docker=nginx
ARG NGINX_VERSION=1.27.1-alpine-slim

FROM nginx:${NGINX_VERSION} AS nginx-builder

ARG NGX_MODULE_PATH=/tmp/ngx_brotli

RUN apk add --no-cache \
            curl \
            git
RUN curl --fail \
         --location \
         --output nginx.tar.gz \
         "http://nginx.org/download/nginx-${NGINX_VERSION%%-*}.tar.gz"
RUN git clone \
        --recursive \
        https://github.com/google/ngx_brotli.git \
        "$NGX_MODULE_PATH"

# For latest build deps see
# https://github.com/nginxinc/docker-nginx/blob/master/mainline/alpine/Dockerfile
RUN apk add --virtual \
            .build-deps \
            \
            --no-cache \
            \
            alpine-sdk \
            bash \
            findutils \
            gcc \
            gd-dev \
            geoip-dev \
            libc-dev \
            libedit-dev \
            libxslt-dev \
            linux-headers \
            make \
            openssl-dev \
            pcre2-dev \
            perl-dev \
            zlib-dev \
            \
            brotli-dev

# Reuse same CLI arguments as the nginx:alpine image used to build.
RUN CONFARGS=$(nginx -V 2>&1 | sed -n -e 's/^.*arguments: //p') \
    tar -xzf nginx.tar.gz && \
    cd nginx-$NGINX_VERSION && \
    ./configure --with-compat $CONFARGS \
                --add-dynamic-module="$NGX_MODULE_PATH" && \
    make && \
    make install

# Save /usr/lib/*.so deps.
RUN mkdir /so-deps && \
    cp --dereference \
       $(ldd /usr/local/nginx/modules/ngx_http_brotli_filter_module.so 2>/dev/null | \
           grep '/usr/lib/' | \
           awk '{ print $3 }' | \
           tr '\n' ' ') \
       /so-deps

# 3. Build customized nginx with Brotli module copied from nginx-builder.
FROM nginx:${NGINX_VERSION} AS runtime

# Update all packages.
RUN apk upgrade --update-cache --no-cache

# Copy Brotli module and dependencies.
COPY --from=nginx-builder \
     /so-deps \
     /usr/lib
COPY --from=nginx-builder \
     /usr/local/nginx/modules/ngx_http_brotli_*_module.so \
     /usr/local/nginx/modules/
