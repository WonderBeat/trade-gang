#!/bin/sh

socat TCP-LISTEN:7878,reuseaddr,fork SYSTEM:"echo HTTP/1.0 200; echo Content-Type\: text/plain; version=0.0.4; echo; cat metrics.prometheus" >/dev/null 2>&1
