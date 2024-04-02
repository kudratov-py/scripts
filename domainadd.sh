#!/usr/bin/bash

# Text Color Variables http://misc.flogisoft.com/bash/tip_colors_and_formatting
#tcLtG="\033[00;37m"    # LIGHT GRAY
#tcDkG="\033[01;30m"    # DARK GRAY
#tcLtR="\033[01;31m"    # LIGHT RED
tcLtGRN="\033[01;32m"  # LIGHT GREEN
#tcLtBL="\033[01;34m"   # LIGHT BLUE
#tcLtP="\033[01;35m"    # LIGHT PURPLE
#tcLtC="\033[01;36m"    # LIGHT CYAN
#tcW="\033[01;37m"      # WHITE
#tcRESET="\033[0m"
#tcORANGE="\033[38;5;209m"


# Check run as sudo user
#if [ "$UID" -ne "0" ]; then
#echo "Please run this script as root user with `sudo -E ./domainadd.sh`"
#exit 1
#fi

#set -e
#set -x
#host=($hostname) # Current hostname


sudo apt update && sudo apt upgrade -y
sudo apt -y install realmd libnss-sss libpam-sss sssd sssd-tools adcli samba-common-bin oddjob oddjob-mkhomedir packagekit
sudo apt -y install cifs-utils openssh-server
sudo apt -y remove --autoremove gnome-initial-setup

read -p "Enter a new computer name in the domain: " pcname
read -p "Enter a domain name: " domain

# Change Hostname
sudo hostnamectl set-hostname "$pcname"."$domain"

# Change /etc/hosts
echo "Change /etc/hosts $pcname.$domain. Created backup /etc/hosts.back"
sudo cp /etc/hosts /etc/hosts.back
sudo chmod 777 /etc/hosts
sudo cat << EOF > sudo /etc/hosts
127.0.0.1       localhost
127.0.0.1       $pcname.$domain
EOF
sudo chmod 644 /etc/hosts

sudo systemctl disable systemd-resolved.service

sudo sed -i '/main/a dns=default' /etc/NetworkManager/NetworkManager.conf

sudo rm /etc/resolv.conf

sudo service NetworkManager restart
sudo apt -y install krb5-user

sudo cp /etc/krb5.conf /etc/krb5.conf.back
sudo cat << EOF > sudo /etc/krb5.conf
[libdefaults]
        default_realm = $domain
        kdc_timesync = 1
        ccache_type = 4
        forwardable = true
        proxiable = true
        fcc-mit-ticketflag = true
[realms]
        $domain =
        {
                kdc = $pcname.$domain
                admin_server = $pcname.$domain
                default_domain = $domain
        }
[domain_realms]
        .$domain = $domain
        $domain = $domain"
EOF

sudo realm discover "$domain"

read -p "Add administrator on PC. Enter ADMIN username: " admin
sudo realm join -U "$admin" "$domain"

# Change config in mkhomedir
sudo sed -i 's/Default: no/Default: yes/' /usr/share/pam-configs/mkhomedir && sudo sed -i 's/Priority: 0/Priority: 900/' /usr/share/pam-configs/mkhomedir && sudo sed -i 's/Session-Interactive-Only: yes/Session-Interactive-Only: no/' /usr/share/pam-configs/mkhomedir

read -t 5 -p "Please choose - Create home directory on login"
sudo pam-auth-update

echo -e "\nEnter a domain username: "
read username

sudo realm permit "$username"@"$domain"

sudo systemctl restart sssd

echo "Added domain user in sudoers"
if [ -f /etc/sudoers.d/domain_users ]; then
        sudo chmod 740 /etc/sudoers.d/domain_users
        echo "$username@$domain ALL=(ALL) ALL" >> /etc/sudoers.d/domain_users
        sudo chmod 0440 /etc/sudoers.d/domain_users
else
        sudo touch "$HOME"/domain_users && sudo chmod 750 "$HOME"/domain_users
        echo "$username@$domain ALL=(ALL) ALL" >> "$HOME"/domain_users
        sudo mv "$HOME"/domain_users /etc/sudoers.d/ && sudo chmod 0440 /etc/sudoers.d/domain_users
fi

# Файл отоборажения версии ОС в АД
version=`lsb_release -r | awk {'print $2'}`
sudo touch /etc/realmd.conf
sudo chmod 777 /etc/realmd.conf
echo -e "[active-directory]\ndefault-client = sssd\nos-name = Ubuntu Workstation\nos-version = $version" > /etc/realmd.conf
sudo chmod 644 /etc/realmd.conf

echo -e "$tcLtGRN"; read -t 3 -p "Rebooting the system."; echo -e "$tcLtGRN"
sudo reboot
