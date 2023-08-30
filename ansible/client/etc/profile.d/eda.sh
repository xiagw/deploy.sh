# shellcheck disable=2148,1090,2086
## /etc/profile.d/eda.sh

_msg() {
    color_off='\033[0m' # Text Reset
    case "$1" in
    red | error | erro) color_on='\033[0;31m' ;;       # Red
    green | info) color_on='\033[0;32m' ;;             # Green
    yellow | warning | warn) color_on='\033[0;33m' ;;  # Yellow
    blue) color_on='\033[0;34m' ;;                     # Blue
    purple | question | ques) color_on='\033[0;35m' ;; # Purple
    cyan) color_on='\033[0;36m' ;;                     # Cyan
    *) unset color_on color_off ;;
    esac
    shift
    echo -e "${color_on}$*${color_off}"
}

startcad() {
    if [ ! -f $cdsinit_home ]; then
        /usr/bin/cp $cdsinit $cdsinit_home
    fi
    if [ -f $cadence_bashrc ]; then
        _msg info "Found $cadence_bashrc and source it"
        source $cadence_bashrc
    else
        _msg warn "Not found $cadence_bashrc"
    fi
}

startmnt() {
    if [ ! -f $cdsinit_home ]; then
        /usr/bin/cp $cdsinit $cdsinit_home
    fi
    if [ -f $mentor_bashrc ]; then
        _msg info "Found and source $mentor_bashrc"
        source $mentor_bashrc
    else
        _msg warn "Not found $mentor_bashrc"
    fi
}

startsyn() {
    [ -f $cdsinit_home ] || /usr/bin/cp $cdsinit $cdsinit_home
    if [ -f $synopysys_bashrc ]; then
        _msg info "Found and source $synopysys_bashrc"
        source $synopysys_bashrc
    else
        _msg warn "Not found $synopysys_bashrc"
    fi
}

copyenv() {
    if [[ -f $cadence_bashrc && ! -f "$PWD"/bashrc ]]; then
        _msg info "Found $cadence_bashrc and copy it"
        /usr/bin/cp -av $cadence_bashrc "$PWD"/
    else
        _msg warn "Not found $cadence_bashrc OR exist $PWD/bashrc"
    fi
    if [[ -d $eda_home/PDKs/share ]]; then
        _msg info "Found $eda_home/PDKs/share and copy it"
        /usr/bin/cp -av $eda_home/PDKs/share/* $PWD/
    fi
}

main() {
    if [[ -d /eda ]]; then
        eda_home=/eda
    elif [ -d /home/eda ]; then
        eda_home=/home/eda
    elif [ -d /opt/eda ]; then
        eda_home=/opt/eda
    else
        _msg warn "not found EDA_HOME"
        return 1
    fi

    cadence_bashrc=$eda_home/cadence/bashrc
    cdsinit=$eda_home/cadence/cdsinit
    cdsinit_home=$HOME/.cdsinit
    mentor_bashrc=$eda_home/mentor/bashrc
    synopysys_bashrc=$eda_home/synopsys/bashrc

    if [[ "$(/usr/bin/id -u)" -gt 999 ]]; then
        _msg info "# Before start Cadence tools, execute:"
        _msg warn "  startcad"
        _msg info "# Before start Synopsys tools, execute:"
        _msg warn "  startsyn"
        # _msg info "# If you want to copy $eda_home/PDKs/share/ to current dir, execute:"
        # _msg warn "  copyenv"
    fi
}

main "$@"
