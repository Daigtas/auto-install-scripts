#!/bin/bash

shopt -s dotglob
export DEBIAN_FRONTEND="noninteractive"

parse_options () 
{
    for i in "$@"
    do
        case $i in
            -h|--help)
                show_help
                exit 0
            ;;
            --path=*)
                gameap_path=${i#*=}
                shift

                if [[ ! -s "${gameap_path}" ]]; then
                    mkdir -p ${gameap_path}

                    if [ "$?" -ne "0" ]; then
                        echo "Unable to make directory: ${gameap_path}." >> /dev/stderr
                        exit 1
                    fi
                fi
            ;;
            --host=*)
                gameap_host=${i#*=}
                shift
            ;;
            --web-server=*)
                web_selected="${i#*=}"
                shift
            ;;
            --database=*)
                db_selected="${i#*=}"
                shift
            ;;
            --github)
                from_github=1
            ;;
        esac
    done
}

show_help ()
{
    echo
    echo "GameAP web auto installator"
}

update_packages_list ()
{
    echo -n "Running apt-get update... "
    apt-get update &> /dev/null

    if [ "$?" -ne "0" ]; then
        echo "Unable to update apt" >> /dev/stderr
        exit 1
    fi

    echo "done."
}

install_packages ()
{
    packages=$@

    echo -n "Installing ${packages}... "
    apt-get install -y $packages &> /dev/null

    if [ "$?" -ne "0" ]; then
        echo "Unable to install ${packages}." >> /dev/stderr
        echo "Package installation aborted." >> /dev/stderr
        exit 1
    fi
    echo "done."
}

add_gpg_key ()
{
    gpg_key_url=$1
    curl -SfL "${gpg_key_url}" 2> /dev/null | apt-key add - &>/dev/null

    if [ "$?" -ne "0" ]; then
      echo "Unable to add GPG key!" >> /dev/stderr
      exit 1
    fi
}

generate_password()
{
    echo $(tr -cd '[:alnum:]' < /dev/urandom | fold -w18 | head -n1)
}

unknown_os ()
{
  echo "Unfortunately, your operating system distribution and version are not supported by this script."
}

detect_os ()
{
  if [[ ( -z "${os}" ) && ( -z "${dist}" ) ]]; then
    if [ -e /etc/lsb-release ]; then
      . /etc/lsb-release

      if [ "${ID}" = "raspbian" ]; then
        os=${ID}
        dist=`cut --delimiter='.' -f1 /etc/debian_version`
      else
        os=${DISTRIB_ID}
        dist=${DISTRIB_CODENAME}

        if [ -z "$dist" ]; then
          dist=${DISTRIB_RELEASE}
        fi
      fi

    elif [ `which lsb_release 2>/dev/null` ]; then
      dist=`lsb_release -c | cut -f2`
      os=`lsb_release -i | cut -f2 | awk '{ print tolower($1) }'`

    elif [ -e /etc/debian_version ]; then
      os=`cat /etc/issue | head -1 | awk '{ print tolower($1) }'`
      if grep -q '/' /etc/debian_version; then
        dist=`cut --delimiter='/' -f1 /etc/debian_version`
      else
        dist=`cut --delimiter='.' -f1 /etc/debian_version`
      fi

      if [ "${os}" = "debian" ]; then 
        case $dist in
            6* ) dist="squeeze" ;;
            7* ) dist="wheezy" ;;
            8* ) dist="jessie" ;;
            9* ) dist="stretch" ;;
            10* ) dist="buster" ;;
            11* ) dist="bullseye" ;;
        esac
      fi

    else
      unknown_os
    fi
  fi

  if [ -z "$dist" ]; then
    unknown_os
  fi

  # remove whitespace from OS and dist name
  os="${os// /}"
  dist="${dist// /}"

  # lowercase
  os=${os,,}
  dist=${dist,,}

  echo "Detected operating system as $os/$dist."
}

gpg_check ()
{
  echo "Checking for gpg..."
  if command -v gpg > /dev/null; then
    echo "Detected gpg..."
  else
    echo "Installing gnupg for GPG verification..."
    apt-get install -y gnupg
    if [ "$?" -ne "0" ]; then
      echo "Unable to install GPG! Your base system has a problem; please check your default OS's package repositories because GPG should work." >> /dev/stderr
      echo "Repository installation aborted." >> /dev/stderr
      exit 1
    fi
  fi
}

curl_check ()
{
  echo "Checking for curl..."
  if command -v curl > /dev/null; then
    echo "Detected curl..."
  else
    echo "Installing curl..."
    apt-get install -q -y curl
    if [ "$?" -ne "0" ]; then
      echo "Unable to install curl! Your base system has a problem; please check your default OS's package repositories because curl should work." >> /dev/stderr
      echo "Repository installation aborted." >> /dev/stderr
      exit 1
    fi
  fi
}

get_package_name ()
{
    package=$1

    if [ "${package}" = "mysql" ]; then
        if [ "${os}" = "debian" ]; then
            package_name="mysql-server"
            case $dist in
                "squeeze" ) package_name="mysql-server" ;;
                "wheezy" ) package_name="mysql-server" ;;
                "jessie" ) package_name="mysql-server" ;;
                "stretch" ) package_name="mysql-server" ;;
                "buster" ) package_name="default-mysql-server" ;;
                "bullseye" ) package_name="default-mysql-server" ;;
                "sid" ) package_name="default-mysql-server" ;;
            esac
        elif [ "${os}" = "ubuntu" ]; then
            package_name="mysql-server"
        else
            package_name="mysql-server"
        fi
    fi

    echo $package_name
}

add_php_repo ()
{
    if [ "${os}" = "debian" ]; then
        add_gpg_key "https://packages.sury.org/php/apt.gpg"
        echo "deb https://packages.sury.org/php/ ${dist} main" | tee /etc/apt/sources.list.d/php.list
    elif [ "${os}" = "ubuntu" ]; then
        LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    fi

    update_packages_list
    php_packages_check 1
}

php_packages_check ()
{
    not_repo=$1
    
    echo "Checking for PHP..."

    echo "Checking for PHP 7.3 version available..."

    if [ ! -z "$(apt-cache policy php | grep 7.3)" ]; then
        echo "PHP 7.3 available"
        php_version="7.3"
        return
    fi
    echo "PHP 7.3 not available..."
    
    echo "Checking for PHP 7.2 version available..."

    if [ ! -z "$(apt-cache policy php | grep 7.2)" ]; then
        echo "PHP 7.2 available"
        php_version="7.2"
        return
    fi

    echo "PHP 7.2 not available..."
    echo "Checking for PHP 7.1 version available..."

    if [ ! -z "$(apt-cache policy php | grep 7.1)" ]; then
        echo "PHP 7.1 available"
        php_version="7.1"
        return
    fi

    echo "PHP 7.1 not available..."

    if [ -z $not_repo ]; then
        echo "Trying to add PHP repo..."
        add_php_repo
    fi
}

install_from_github ()
{
    install_packages git

    echo "Installing Composer..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    echo "done"
    
    echo "Installing NodeJS..."
    curl -sL https://deb.nodesource.com/setup_10.x | bash - &> /dev/null
    install_packages nodejs
    echo "done"

    git clone https://github.com/et-nik/gameap.git $gameap_path
    if [ "$?" -ne "0" ]; then
        echo "Unable to download from GitHub" >> /dev/stderr
        exit 1
    fi

    cd $gameap_path
    echo "Installing Composer packages..."
    echo "This may take a long while..."
    composer install --no-dev --optimize-autoloader &> /dev/null
    if [ "$?" -ne "0" ]; then
        echo "Unable to install Composer packages. " >> /dev/stderr
        exit 1
    fi
    echo "done"

    cp .env.example .env

    echo "Generating encryption key..."
    php artisan key:generate --force
    echo "done"

    echo "Installing NodeJS packages..."
    npm install &> /dev/null
    if [ "$?" -ne "0" ]; then
        echo "Unable to install NodeJS packages. " >> /dev/stderr
        echo "Styles building aborted." >> /dev/stderr
        exit 1
    fi
    echo "done"

    echo "Building the styles..."
    npm run prod &> /dev/null
    if [ "$?" -ne "0" ]; then
        echo "Unable to build styles. " >> /dev/stderr
        echo "Styles building aborted." >> /dev/stderr
        exit 1
    fi
    echo "done"
}

install_from_official_repo ()
{
    cd $gameap_path

    echo "Downloading GameAP archive..."
    curl -SfL http://packages.gameap.ru/gameap/latest \
        --output gameap.tar.gz &> /dev/null
    
    if [ "$?" -ne "0" ]; then
        echo "Unable to download GameAP. "
        echo "Installation GameAP aborted."
        exit 1
    fi
    echo "done"

    echo "Unpacking GameAP archive..."
    tar -xvf gameap.tar.gz gameap -C ./ &> /dev/null
    if [ "$?" -ne "0" ]; then
        echo "Unable to unpack GameAP. " >> /dev/stderr
        echo "Installation GameAP aborted." >> /dev/stderr
        exit 1
    fi
    echo "done"
    mv gameap/* ./
    rmdir gameap
    rm gameap.tar.gz

    cp .env.example .env

    echo "Generating encryption key..."
    php artisan key:generate --force
    echo "done"
}

mysql_setup ()
{
    #while true; do read -p "Enter MySQL root password: " database_root_password; done
    #while true; do read -p "Enter MySQL user name: " database_user_name; done
    #while true; do read -p "Enter MySQL user password: " database_user_password; done

    if command -v mysqld > /dev/null; then
        echo "Detected installed mysql..."

        echo "MySQL configuring skipped."
        echo "Please configure MySQL manually."

        mysql_manual=1
    else
        database_root_password=$(generate_password)
        database_user_name="gameap"
        database_user_password=$(generate_password)

        install_packages $(get_package_name mysql)
        unset mysql_package

        service mysql start

        mysql -u root -e 'CREATE DATABASE IF NOT EXISTS `gameap`' &> /dev/null
        if [ "$?" -ne "0" ]; then echo "Unable to create database. MySQL seting up failed." >> /dev/stderr; exit 1; fi

        mysql -u root -e "use mysql;\
            update user set password=PASSWORD(\"${database_root_password}\") where User='root';\
            flush privileges;" &> /dev/null

        if [ "$?" -ne "0" ]; then echo "Unable to set database root password. MySQL seting up failed." >> /dev/stderr; exit 1; fi

        service mysql restart

        mysql -u root -p${database_root_password} -e "use mysql;\
            GRANT SELECT ON *.* TO '${database_user_name}'@'%';\
            GRANT ALL PRIVILEGES ON gameap.* TO '${database_user_name}'@'%' IDENTIFIED BY '${database_user_password}';"

        if [ "$?" -ne "0" ]; then echo "Unable to set database user password. MySQL seting up failed." >> /dev/stderr; exit 1; fi
    fi
}

nginx_setup ()
{
    if command -v nginx > /dev/null; then
        echo "Detected installed nginx..."
    else
        add_gpg_key "https://nginx.org/keys/nginx_signing.key"
        
        if [ "${os}" = "debian" ]; then
            echo "deb http://nginx.org/packages/debian/ ${dist} nginx" | tee /etc/apt/sources.list.d/nginx.list
        elif [ "${os}" = "ubuntu" ]; then
            echo "deb http://nginx.org/packages/ubuntu/ ${dist} nginx" | tee /etc/apt/sources.list.d/nginx.list
        fi

        update_packages_list
        install_packages nginx
    fi

    curl -SfL https://raw.githubusercontent.com/gameap/auto-install-scripts/master/web-server-configs/nginx-no-ssl.conf \
        --output /etc/nginx/conf.d/gameap.conf &> /dev/null

    if [ "$?" -ne "0" ]; then
        echo "Unable to download default nginx config" >> /dev/stderr
        echo "Nginx configuring skipped" >> /dev/stderr
        return
    fi

    sed -i "s/^\(\s*user\s*\).*$/\1www-data\;/" /etc/nginx/nginx.conf

    sed -i "s/^\(\s*server\_name\s*\).*$/\1${gameap_host}\;/" /etc/nginx/conf.d/gameap.conf
    sed -i "s/^\(\s*root\s*\).*$/\1${gameap_path//\//\\/}\;/" /etc/nginx/conf.d/gameap.conf
    sed -i "s/^\(\s*root\s*\).*$/\1${gameap_path//\//\\/}\;/" /etc/nginx/conf.d/gameap.conf

    sock=unix:/var/run/php/php${php_version}-fpm.sock
    sed -i "s/^\(\s*fastcgi_pass\s*\).*$/\1${fastcgi_pass//\//\\/}\;/" /etc/nginx/conf.d/gameap.conf

    service nginx start
    service php${php_version}-fpm start
}

apache_setup ()
{
    if command -v apache2 > /dev/null; then
        echo "Detected installed apache..."
    else
        install_packages apache2 libapache2-mod-php${php_version}
    fi

    curl -SfL https://raw.githubusercontent.com/gameap/auto-install-scripts/master/web-server-configs/apache-no-ssl.conf \
        --output /etc/apache/sites-available/gameap.conf &> /dev/null

    if [ "$?" -ne "0" ]; then
        echo "Unable to download default Apache config" >> /dev/stderr
        echo "Apache configuring skipped" >> /dev/stderr
        return
    fi

    ln -s /etc/apache/sites-enabled/gameap.conf /etc/apache/sites-available/gameap.conf

    sed -i "s/^\(\s*ServerName\s*\).*$/\1${gameap_host}/" ./web-server-configs/apache-no-ssl.conf
    sed -i "s/^\(\s*DocumentRoot\s*\).*$/\1${path//\//\\/}/" ./web-server-configs/apache-no-ssl.conf
    sed -i "s/^\(\s*[\<{1}]Directory\s*\).*$/\1${path//\//\\/}>/" ./web-server-configs/apache-no-ssl.conf

    /etc/init.d/apache2 start
}

ask_user ()
{
    if [ -z "${gameap_path}" ]; then
        while true; do
            echo 
            read -p "Enter gameap installation path (Example: /var/www/gameap): " gameap_path
            if [[ ! -s "${gameap_path}" ]]; then
                    read -p "${gameap_path} not found. Do you wish to make directory? (Y/n): " yn
                    case $yn in
                        [Yy]* ) mkdir -p ${gameap_path}; break;;
                    esac
            else 
                break;
            fi
        done
    fi

    if [ -z "${gameap_host}" ]; then
        read -p "Enter gameap host (example.com): " gameap_host
    fi

    if [ -z "${db_selected}" ]; then
        echo
        echo "Select database to install and configure"

        echo "1) MySQL"
        echo "2) SQLite"
        echo "3) None. Do not install a database"
        echo 

        while true; do
            read -p "Enter number: " db_selected
            case $db_selected in
                1* ) db_selected="mysql"; echo "Okay! Will try install MySQL..."; break;;
                2* ) db_selected="sqlite"; echo "Okay! Will try install SQLite..."; break;;
                3* ) db_selected="none"; echo "Okay! ..."; break;;
                * ) echo "Please answer 1-3.";;
            esac
        done
    fi

    if [ -z "${web_selected}" ]; then
        echo
        echo "Select Web-server to install and configure"

        echo "1) Nginx"
        echo "2) Apache"
        echo "3) None. Do not install a Web Server"
        echo 

        while true; do
            read -p "Enter number: " web_selected
            case $web_selected in
                1* ) web_selected="nginx"; echo "Okay! Will try to install Nginx..."; break;;
                2* ) web_selected="apache"; echo "Okay! Will try install Apache..."; break;;
                3* ) web_selected="none"; echo "Okay! ..."; break;;
                * ) echo "Please answer 1-3.";;
            esac
        done
    fi
}

main ()
{
    detect_os

    ask_user

    update_packages_list

    curl_check
    gpg_check

    install_packages software-properties-common apt-transport-https

    # add_gpg_key "http://packages.gameap.ru/gameap-rep.gpg.key"
    # echo "deb http://packages.gameap.ru/debian/ ${dist} main" > /etc/apt/sources.list.d/gameap.list
    # update_packages_list

    php_packages_check

    if [ -z "${php_version}" ]; then
        echo "Unable to find PHP >= 7.1" >> /dev/stderr
        exit 1
    fi

    install_packages php${php_version}-common \
        php${php_version}-common \
        php${php_version}-cli \
        php${php_version}-fpm \
        php${php_version}-pdo \
        php${php_version}-mysql \
        php${php_version}-redis \
        php${php_version}-curl \
        php${php_version}-bz2 \
        php${php_version}-zip \
        php${php_version}-xml \
        php${php_version}-mbstring \
        php${php_version}-bcmath
    
    if [ ! -z ${from_github} ]; then
        install_from_github
    else
        install_from_official_repo
    fi

    case $db_selected in
        "mysql" )
            mysql_setup

            sed -i "s/^\(DB\_CONNECTION\s*=\s*\).*$/\1mysql/" .env
            sed -i "s/^\(DB\_DATABASE\s*=\s*\).*$/\1gameap/" .env
            sed -i "s/^\(DB\_USERNAME\s*=\s*\).*$/\1${database_user_name}/" .env
            sed -i "s/^\(DB\_PASSWORD\s*=\s*\).*$/\1${database_user_password}/" .env
        ;;

        "sqlite" ) 
            install_packages php${php_version}-sqlite
            database_name="${gameap_path}/database.sqlite"
            touch $database_name

            sed -i "s/^\(DB\_CONNECTION\s*=\s*\).*$/\1sqlite/" .env
            sed -i "s/^\(DB\_DATABASE\s*=\s*\).*$/\1${database_name//\//\\/}/" .env
        ;;
    esac

    if [ "${db_selected}" != "none" ]; then
        echo "Migrating database..."
        php artisan migrate --seed
        if [ "$?" -ne "0" ]; then
            echo "Unable to migrate database." >> /dev/stderr
            echo "Database seting up aborted." >> /dev/stderr
            exit 1
        fi
        echo "done"
    fi

    if [ "${web_selected}" != "none" ]; then
        case $web_selected in
            "nginx" ) nginx_setup;;
            "apache" ) apache_setup;;
        esac
    fi

    chown -R www-data:www-data ${gameap_path}

    echo "---------------------------------"
    echo "DONE!"
    echo 
    echo "GameAP file path: ${gameap_path}"
    echo

    if [ "${db_selected}" = "sqlite" ]; then 
        echo "Database: ${database_name}"
    else
        if [ ! -z "$database_root_password" ]; then echo "Database root password: ${database_root_password}"; fi
        echo "Database name: gameap"
        if [ ! -z "$database_user_name" ]; then echo "Database user name: ${database_user_name}"; fi
        if [ ! -z "$database_user_password" ]; then echo "Database user password: ${database_user_password}"; fi
    fi

    echo 
    echo "Administrator credentials"
    echo "Login: admin"
    echo "Password: fpwPOuZD"
    echo
    echo "Host: http://${gameap_host}"
    echo
    echo "---------------------------------"
}

parse_options $@
main