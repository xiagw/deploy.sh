#!/usr/bin/bash

if [ -d /home/eda ]; then
    eda_home=/home/eda
else
    eda_home=/eda
fi
# bin_lmgrd=$eda_home/synopsys/scl/2018.06/linux64/bin/lmgrd
# bin_lmutil=$eda_home/synopsys/scl/2018.06/linux64/bin/lmutil
bin_lmgrd=$eda_home/synopsys/scl/2021.03/linux64/bin/lmgrd
bin_lmutil=$eda_home/synopsys/scl/2021.03/linux64/bin/lmutil
bin_lmstat=$eda_home/synopsys/scl/2021.03/linux64/bin/lmstat
path_lic=$eda_home/synopsys/license
file_lic=$path_lic/$(hostname -s).license.dat
file_log=$path_lic/$(hostname -s).debug.log

if [ ! -f "$file_lic" ]; then
    file_lic=$path_lic/license.dat
fi
for file in "$file_lic" $bin_lmgrd $bin_lmutil $bin_lmstat; do
    if [ ! -f "$file" ]; then
        echo "Not found $file, exit 1."
        exit 1
    fi
done

case "$1" in
start)
    $bin_lmgrd -c "$file_lic" -l "$file_log"
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
    echo "Usage: $(basename "$0") [ start | stop | restart | help ]"
    ;;
esac
