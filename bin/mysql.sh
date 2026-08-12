#!/usr/bin/env bash

create_mysql_user() {
    local user="$1" f mycnf cmd password_rand
    [[ -z "$user" ]] && retrun 1
    select f in $HOME/.my.cnf $HOME/.my.*.cnf $HOME/.my.cnf.* quit; do
        mycnf="$f"
        break
    done
    cmd=$(command -v mycli || command -v mysql || return 1)
    cmd="$cmd --defaults-file=$mycnf"

    password_rand=$(openssl rand -base64 20 | tr -dc A-Za-z0-9 | head -c16)
    [ -z "$password_rand" ] && password_rand="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c16)"
    # create user with the random password
    # mysql --defaults-extra-file=/path/to/${server}.cnf -e "CREATE USER '${user}'@'%' IDENTIFIED BY '${password_rand}'; GRANT ALL PRIVILEGES ON ${read_db_name}.* TO '${user_name}'@'%';"
    if $cmd -e "show create user $user;" | grep -qw "$user"; then
        echo -e "\n!!!! User $user exist, give up !!!!"
    else
        $cmd -e "CREATE USER '${user}'@'%' IDENTIFIED BY '${password_rand}'; GRANT ALL PRIVILEGES ON ${user}.* TO '${user}'@'%';"
        echo "Username=${user} / Password=${password_rand}"
    fi
}

create_mysql_user "$@"
