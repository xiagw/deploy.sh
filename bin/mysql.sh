#!/usr/bin/env bash

create_mysql_user() {
    # check if required ~/.my.cnf is exist
    select mysql_conf in $HOME/.my.cnf $HOME/.my.*.cnf quit; do
        cp -avf "$mysql_conf" "$HOME/.my.cnf"
        break
    done
    cmd=$(command -v mycli || command -v mysql || return 1)
    if [[ -z "$1" ]]; then
        read -rp 'Enter MySQL username: ' read_user_name
        user_name=${read_user_name:? ERR: empty user name}
    else
        user_name="$1"
    fi
    # generate a random password
    password_rand=$(openssl rand -base64 20 | tr -dc A-Za-z0-9 | head -c14)
    [ -z "$password_rand" ] &&
        password_rand="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c14)"
    # create user with the random password
    # mysql --defaults-extra-file=/path/to/${server}.cnf -e "CREATE USER '${user_name}'@'%' IDENTIFIED BY '${password_rand}'; GRANT ALL PRIVILEGES ON ${read_db_name}.* TO '${user_name}'@'%';"
    if $cmd -e "show create user $user_name;" | grep "$user_name"; then
        echo -e "\n!!!! User $user_name exist, give up !!!!"
    else
        $cmd -e "CREATE USER '${user_name}'@'%' IDENTIFIED BY '${password_rand}'; GRANT ALL PRIVILEGES ON ${user_name}.* TO '${user_name}'@'%';"
        echo "Username=${user_name}/Password=${password_rand}"
    fi
}

create_mysql_user "$@"
