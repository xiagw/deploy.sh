# shellcheck disable=1046,1047,1072,1073
## /etc/profile.d/eda.csh

if ( -d /home/eda ) then
    setenv eda_home /home/eda
else
    setenv eda_home /eda
endif

setenv file_cadence $eda_home/cadence/cshrc
setenv file_cdsinit $eda_home/cadence/cdsinit
setenv file_mentor $eda_home/mentor/cshrc
setenv file_synopsys $eda_home/synopsys/cshrc
if ( ! -f $HOME/.cdsinit ) then
    cp $file_cdsinit $HOME/.cdsinit
endif

alias startcad "source $file_cadence"
alias cad "source $file_cadence"
alias startmnt "source $file_mentor"
alias mnt "source $file_mentor"
alias startsyn "source $file_synopsys"
alias syn "source $file_synopsys"
