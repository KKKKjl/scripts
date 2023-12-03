#!/bin/bash

function inspect_docker_container() {
    local action="$1"
    local cids=("${@:2}")

    for cid in "${cids[@]}"; do
        read -r name < <(docker inspect $cid --format='{{.Name}}')
        mapfile -t PORT_PROTO_LIST < <(docker inspect $cid --format='{{range $p, $conf := .NetworkSettings.Ports}}{{with $conf}}{{$p}}{{"\n"}}{{end}}{{end}}' | sed '/^[[:blank:]]*$/d')

        for PORT_PROTO in "${PORT_PROTO_LIST[@]}"; do
            if [[ "$action" = "nginx" ]] && [[ "${PORT_PROTO}" = */tcp ]]; then
                mkdir -p /etc/nginx/conf.d/ && update_nginx_rule "${name#*/}" "${PORT_PROTO%/*}"
            fi

            if [[ "$action" = "ufw" ]]; then
                update_ufw_rule "${name#*/}" "${PORT_PROTO}"
            fi
        done
    done
}

function update_ufw_rule() {
    local name="$1"
    local port="$2"

    ufw-docker allow $name $port
    echo "Update ufw rules for $name $port"
}

function update_nginx_rule() {
    local name="$1"
    local port="$2"

    nginx_conf="/etc/nginx/conf.d/${name}.conf"

    echo "
server {
    listen 443 ssl;
    server_name ${name}.llfss.shop;

    ssl_certificate /etc/nginx/conf.d/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/conf.d/ssl/key.pem;

    location / {
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header Range \$http_range;
        proxy_set_header If-Range \$http_if_range;
        proxy_redirect off;
        proxy_pass http://${name}:${port};
        client_max_body_size 2000m;
    }
}
    " >"$nginx_conf"
    echo "Updated Nginx rules for $name $port"
}

function reload_nginx() {
    local nginx_cid=$(docker ps -q -f name=nginx)

    if [[ -z "$nginx_cid" ]]; then
        echo "Nginx container not found"
        exit 1
    fi

    if docker exec -it "$nginx_cid" nginx -t; then
        docker exec -it "$nginx_cid" nginx -s reload
        echo "Reloaded Nginx"
    else
        echo "Nginx configuration test failed. Check Nginx configuration."
        exit 1
    fi
}

function cleanup_nginx() {
    local nginx_cid=$(docker ps -q -f name=nginx)

    [[ -z "$nginx_cid" ]] && echo "Nginx container not found" && exit 1
    rm -rf /etc/nginx/conf.d/*
    docker exec -it $nginx_cid nginx -s reload
}

# main

action="${1:-help}"
case "$action" in
"help")
    echo "Usage: $0 [action]"
    echo "  action: help, update [nginx|ufw]"
    ;;
"update")
    shift || true
    ;&
"nginx" | "ufw")
    cids=($(docker ps -q -f "label=${1}.expose=true"))
    inspect_docker_container "${1}" "${cids[@]}"

    if [[ "${1}" = "nginx" ]]; then
        reload_nginx
    fi
    ;;
*)
    echo "Unknown action: $action"
    exit 1
    ;;
esac
