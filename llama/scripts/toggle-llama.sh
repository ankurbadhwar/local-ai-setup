#!/bin/sh

if systemctl --user is-active --quiet llama-server; then
    systemctl --user stop llama-server
else
    systemctl --user start llama-server
fi
