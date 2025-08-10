#!/bin/sh

#FETCH_URL="http://127.0.0.1:8880/random-proxies?count=300" MQTT="10.46.114.82" MOTHERSHIP="127.0.0.1:8080" CATALOG=161 insecure=true TLD=com ./zig-out/bin/app
#socks_proxy="socks5://10.88.101.77:1080" MQTT="10.46.114.82" MOTHERSHIP="127.0.0.1:8080" CATALOG=48 insecure=true TLD=com ./zig-out/bin/app
#ANONYMIZER="http://127.0.0.1:8880/scrape" MQTT="10.46.114.82" MOTHERSHIP="127.0.0.1:8080" CATALOG=161 insecure=true TLD=info ./zig-out/bin/app
#MQTT="10.46.114.82" MOTHERSHIP="127.0.0.1:8080" CATALOG=48 insecure=true TLD=com ./zig-out/bin/app
#ANONYMIZER="http://127.0.0.1:8765/scrape" MQTT="10.46.114.82" MOTHERSHIP="127.0.0.1:8080" CATALOG=161 insecure=true TLD=info ./zig-out/bin/app

DOMAIN="https://upbit.gladiators.dev" MOTHERSHIP="127.0.0.1:8081" time -l ./zig-out/bin/upbit
