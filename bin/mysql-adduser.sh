#!/usr/bin/env bash

create_mysql_user() {
    # check if required ~/.my.cnf is exist
    select mysql_conf in $HOME/.my.cnf.* quit; do
        cp -avf $mysql_conf $HOME/.my.cnf
        break
    done
    if [ ! -f $HOME/.my.cnf ]; then
        echo "Not found $HOME/.my.cnf, exit"
        return 1
    fi
    if command -v mysql >/dev/null; then
        bin_mysql=mysql
    elif command -v mycli >/dev/null; then
        bin_mysql=mycli
    else
        echo "Not found mysql cli, exit"
        return 1
    fi
    if [[ -z "$1" ]]; then
        read -rp 'Enter MySQL username: ' read_user_name
        user_name=${read_user_name:? ERR: empty user name}
    else
        user_name="$1"
    fi
    # generate a random password
    password_rand=$(openssl rand -base64 20 | tr -dc A-Za-z0-9 | head -c10)
    if [ -z "$password_rand" ]; then
        password_rand="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c10)"
    fi
    # create user with the random password
    # mysql --defaults-extra-file=/path/to/${server}.cnf -e "CREATE USER '${user_name}'@'%' IDENTIFIED BY '${password_rand}'; GRANT ALL PRIVILEGES ON ${read_db_name}.* TO '${user_name}'@'%';"
    if mycli -e 'show create user chenlong;' | grep "$user_name"; then
        echo -e "\n!!!! User $user_name exist, give up !!!!"
    else
        $bin_mysql -e "CREATE USER '${user_name}'@'%' IDENTIFIED BY '${password_rand}'; GRANT ALL PRIVILEGES ON ${user_name}.* TO '${user_name}'@'%';"
        # print the username and password
        echo "Username: ${user_name}  /  Password: ${password_rand}"
    fi

}

create_mysql_user "$@"
