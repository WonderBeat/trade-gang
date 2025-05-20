#!/bin/sh

#FETCH_URL="http://127.0.0.1:8880/random-proxies?count=300" MQTT="10.46.114.82" MOTHERSHIP="127.0.0.1:8080" CATALOG=48 insecure=true TLD=com ./zig-out/bin/app
ANONYMIZER="http://127.0.0.1:8880/scrape" MQTT="10.46.114.82" MOTHERSHIP="127.0.0.1:8080" CATALOG=48 insecure=true TLD=com ./zig-out/bin/app
