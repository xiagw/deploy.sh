#!/usr/bin/bash

_vnc_status() {
    echo -e "\nList all existing vnc port...\n"
    ss -4lntu | grep '\:59..\ '
    echo '##########################################'
    echo -e "\n##  List MINE vnc port...\n"
    vncserver -list
    echo '##########################################'
}

_vnc_start() {
    ## find available port
    vnc_port=5901
    while ss -4lntu | grep -q "\:$vnc_port\ "; do
        vnc_port=$((vnc_port + 1))
    done
    echo "Using empty port: $vnc_port"
    vncserver :$((vnc_port - 5900))
}

_vnc_stop() {
    echo
    echo "If you want to stop :1, then input 1"
    echo "If you want to stop :2, then input 2"
    echo "If you want to stop :3, then input 3"
    echo
    read -rp "Please input vnc number: " vnc_port
    vncserver -kill :"${vnc_port:?ERR: empty vnc number}"
}

case "$1" in
start)
    _vnc_start
    ;;
stop)
    _vnc_status
    _vnc_stop
    ;;
restart)
    _vnc_stop
    sleep 2
    _vnc_start
    ;;
status)
    _vnc_status
    ;;
*)
    echo "Usage: $(basename "$0") [ status | start | stop | restart ]"
    ;;
esac
