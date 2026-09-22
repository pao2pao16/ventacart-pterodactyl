#!/bin/bash
# Pterodactyl's contract: the egg's startup line arrives in $STARTUP with its
# {{VARIABLES}} unexpanded. Expand them against the environment and hand
# over the process.

cd /home/container || exit 1

MODIFIED_STARTUP=$(echo -e "${STARTUP:-ventacart-boot}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo -e "\033[1;33mcontainer@pterodactyl~\033[0m ${MODIFIED_STARTUP}"

eval "exec ${MODIFIED_STARTUP}"
