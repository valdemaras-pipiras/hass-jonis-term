#!/usr/bin/env bash

##
# Caching idea and some pieces of code is borrowed from the:
# https://stackoverflow.com/questions/11900239/can-i-cache-the-output-of-a-command-on-linux-from-cli
##

HOSTNAME=${JTHOST:192.168.0.2}
PORT=${JTPORT:9000}
ALWAYS_SAVE=1

ARGS="$@"
ACTION="$1"
CMD="$2"
CONNECTION="$HOSTNAME $PORT"
NC="$(which nc 2>&1>/dev/null | wc -l)"
PROG="$(basename $0)"
EXPIRY=${EXPIRY:-10}
TS=$(($(date +"%s")-${EXPIRY}))
EXPIRE_DATE=$(date +'%Y-%m-%dT%H:%M:%S%z' -d"@$TS")
HASH=$(echo "$ARGS" | md5sum | awk '{print $1}')
CACHEDIR="/tmp/.cache/jt"
CACHEFILE="$CACHEDIR/$HASH"

##
# Functions()
##
function send() {
   # A bit of a hack, controller returns cached body of the last command, sending the same command twice does the job
   RES=$(echo -e "$1" | nc -w 1 $CONNECTION 2>&1>/dev/null && echo -e "$1" | nc -w 1 $CONNECTION)
   if [[ $(echo $RES | wc -l) -eq 0 ]]; then
       # Failback, resend one more time in 1s, in case of empty result received initially
       sleep 1
       RES=$(echo -e "$1" | nc -w 1 $CONNECTION)
   fi
   echo $RES
}
function get_temp() {
    echo $(send "\x1B\n0?1\x1B\r\r")
}
function get_ct() {
    echo $(send "\x1B\n0#6:0\x1B\r\r")
}
function set_ct() {
    [[ $# -ne 1 ]] && echo "[ERROR] 'Port:Value' variable should be provided as additional argument" && exit 1
    port=$(echo $1 | cut -d: -f1)
    idx=8
    value=$(echo $1 | cut -d: -f2)
    echo $(send "\x1B\n0@K:${port},${idx},${value}\x1B\r\r")
    [[ $ALWAYS_SAVE -eq 1 ]] && save
}
function get_output() {
    [[ $# -ne 1 ]] && echo "[ERROR] Port number should be provided as additional argument" && exit 1
    echo $(send "\x1B\n0?8:"$1"\x1B\r")
}
function get_opmode() {
    echo $(send "\x1B\n0#6:0\x1B\r")
}
function save() {
    echo $(echo -e "\x1B\n0w2\x1b\r" | nc -w 1 $CONNECTION 2>&1)
}

##
# Main()
##
[[ $# -lt 2 ]] && echo "[ERROR] No arguments provided, usage: $PROG cmd arg1 ... argN" && exit 1
[[ $NC -gt 0 ]] && echo "[ERROR] There is no nc (netcat) program installed" && exit 1

# Create caching directory if not available
if [ ! -d "${CACHEDIR}" ]; then
    mkdir -p "${CACHEDIR}"
fi

case $ACTION in
  "get")
    # Cache GET responses for the period in seconds provided in EXPIRY variable
    if [[ -e $CACHEFILE ]] && [[ $(date -Is -r "$CACHEFILE") > $EXPIRE_DATE ]]; then
      cat "$CACHEFILE"
    else
      eval "${ACTION}_${CMD} $3" | tee "$CACHEFILE"
    fi
  ;;
  "set")
    # Don't use caching for SET commands
    eval "${ACTION}_${CMD} $3"
  ;;
  *)
    echo "[ERROR] Wrong action is used, possible actions: get or set" && exit 1
  ;;
esac

exit
