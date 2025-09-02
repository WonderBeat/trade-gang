#!/bin/sh

#FETCH_URL="http://127.0.0.1:8880/random-proxies?count=300" MQTT="10.46.114.82" MOTHERSHIP="127.0.0.1:8080" CATALOG=161 insecure=true TLD=com ./zig-out/bin/app
#socks_proxy="socks5://10.88.101.77:1080" MQTT="10.46.114.82" MOTHERSHIP="127.0.0.1:8080" CATALOG=48 insecure=true TLD=com ./zig-out/bin/app
#ANONYMIZER="http://127.0.0.1:8880/scrape" MQTT="10.46.114.82" MOTHERSHIP="127.0.0.1:8080" CATALOG=161 insecure=true TLD=info ./zig-out/bin/app
#MQTT="10.46.114.82" MOTHERSHIP="127.0.0.1:8080" CATALOG=48 insecure=true TLD=com ./zig-out/bin/app
#ANONYMIZER="http://127.0.0.1:8765/scrape" MQTT="10.46.114.82" MOTHERSHIP="127.0.0.1:8080" CATALOG=161 insecure=true TLD=info ./zig-out/bin/app

#QUERY_TIMEOUT=5000 INTERVAL=1000 PROXY_LIST="http://127.0.0.1:8880/random-self-managed-proxies?count=10" DOMAIN="https://upbit.gladiators.dev" MOTHERSHIP="127.0.0.1:8081" time -l ./zig-out/bin/upbit

#QUERY_TIMEOUT=3000 socks_proxy="socks5://10.88.101.77:1080" INTERVAL=1000 DOMAIN="https://upbit.gladiators.dev" MOTHERSHIP="127.0.0.1:8081" time -l ./zig-out/bin/upbit
