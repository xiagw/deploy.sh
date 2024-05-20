#!/usr/bin/bash

for d in /eda /home/eda /opt/eda; do
    [ -d "$d" ] && eda_home="$d" && break
done
[ -z "$eda_home" ] && echo "Not found EDA directory" && exit 1

# bin_dir=$eda_home/synopsys/scl/2018.06/linux64/bin
bin_dir=$eda_home/synopsys/scl/2021.03/linux64/bin
bin_lmgrd=$bin_dir/lmgrd
bin_lmutil=$bin_dir/lmutil
bin_lmstat=$bin_dir/lmstat

host_name="$(hostname -s)"
path_lic=$eda_home/synopsys/license
file_lic=$path_lic/${host_name}.license.dat
if [ -w "$path_lic" ]; then
    file_log=$path_lic/${host_name}.debug.log
else
    file_log=$HOME/${host_name}.debug.log
fi

for file in "$file_lic" $bin_lmgrd $bin_lmutil $bin_lmstat; do
    if [ -f "$file" ]; then
        echo "Found $file,"
    else
        echo "Not found $file, exit 1."
        exit 1
    fi
done

case "$1" in
start)
    $bin_lmgrd -l "$file_log" -c "$file_lic"
    ;;
stop)
    $bin_lmutil lmdown -c "$file_lic" -q
    ;;
restart)
    stop
    sleep 2
    start
    ;;
status)
    $bin_lmstat
    ;;
*)
    echo "Usage: $(basename "$0") [ start | stop | restart ]"
    ;;
esac
