#!/bin/bash

# 1. THIS SHOULD BE SET FOR YOUR LOCAL TZ
TIMEZONE="America/Chicago"

# 2. ADD A GROUP HERE IF YOU WANT ONE ADDED TO SUDOERS. WORKS FOR $AD GROUPS.
# LEAVE EMPTY ("") IF NOT IN USE
SUDOGROUP="SUDOers"
# note: I really recommend you set this so that an elevated domain user can
#  administrate these remotely. The alternatives are (a) local users, whose
#  passwords can't be changed easily, or (b) SSH keys for every user, which
#  is a pita and not always practical for large organizations. Local sudo
#  users are trouble.

# 3. PUT YES/yEs HERE IF YOU WANT ANSIBLE, ANYTHING ELSE IF NOT
ANSIBLE="YES"

# 4. OPTION HERE TO RESTRICT SSH LOGINS TO A PARTICULAR GROUP. SHOULD WORK 
#  FOR LOCAL GROUPS OR AD GROUPS
SSHGROUPS="users ssh_ad_users"
# note: case-sensitivity here seems inconsistent, use caution when
#  naming your groups for SSH.

# Script starts here

# You need to be root, sorry.
if [[ $EUID -ne 0 ]]; then
	echo "This script requires elevated privileges to run. Are you root?"
	exit
fi

HOSTNAME=$(hostname)

echo 'FQDN of DC ("realm.domain.tld"):'
read FQDN
echo 'Username with domain machine add authority:'
read USERNAME
echo 'Password:'
read -s PASSWORD

# Read in the date for backup tagging
DATE=$(date +"%Y%m%d%H%M")

# Parse fqdn
REALM_U=$(echo $FQDN | awk 'BEGIN {FS="."}{print toupper($1)}')
DOMAIN_U=$(echo $FQDN | awk 'BEGIN {FS="."}{print toupper($2)}')
TLD_U=$(echo $FQDN | awk 'BEGIN {FS="."}{print toupper($3)}')

REALM_L=$(echo ${REALM_U,,})
DOMAIN_L=$(echo ${DOMAIN_U,,})
TLD_L=$(echo ${TLD_U,,})

ANSIBLE=$(echo ${ANSIBLE,,})

echo "Updating and upgrading..."
apt-get update &>/dev/null
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y &>/dev/null

echo "Installing new packages..."
# noninteractive suppresses blue screens for kerberos
DEBIAN_FRONTEND=noninteractive apt-get install winbind samba \
libnss-winbind libpam-winbind krb5-config krb5-locales python-apt \
krb5-user sudo ntp -y -q &>/dev/null || ( echo "Failed to install some packages. Quitting." && exit 1 )

echo "Backing up kerberos config..."
FILE="/etc/krb5.conf"
touch $FILE
mv $FILE $FILE.backup$DATE

echo "Writing new kerberos config..."
/bin/cat <<EOT >> $FILE

[libdefaults]
 ticket_lifetime = 24000
 default_realm = $REALM_U.$DOMAIN_U.$TLD_U
 default_tgs_entypes = rc4-hmac des-cbc-md5
 default_tkt__enctypes = rc4-hmac des-cbc-md5
 permitted_enctypes = rc4-hmac des-cbc-md5
 dns_lookup_realm = true
 dns_lookup_kdc = true
 dns_fallback = yes

[realms]
 $REALM_U.$DOMAIN_U.$TLD_U = {
  kdc = $DOMAIN_L.$TLD_L:88
  default_domain = $DOMAIN_L.$TLD_L
 }

[domain_realm]
 .$DOMAIN_L.$TLD_L = $REALM_U.$DOMAIN_U.$TLD_U
 $DOMAIN_L.$TLD_L = $REALM_U.$DOMAIN_U.$TLD_U

[appdefaults]
 pam = {
   debug = false
   ticket_lifetime = 36000
   renew_lifetime = 36000
   forwardable = true
   krb4_convert = false
 }

[logging]
 default = FILE:/var/log/krb5libs.log
 kdc = FILE:/var/log/krb5kdc.log
 admin_server = FILE:/var/log/kadmind.log

EOT

echo "Backing up smb.conf..."
FILE="/etc/samba/smb.conf"
touch $FILE
mv $FILE $FILE.backup$DATE

echo "Writing new Samba config..."
/bin/cat <<EOT >> $FILE

[global]
   security = ads
   realm = $DOMAIN_L.$TLD_L
   password server = $REALM_L.$DOMAIN_L.$TLD_L
   workgroup = nichnologist
   winbind separator = +
   wins server = $REALM_L.$DOMAIN_L.$TLD_L
   idmap config *:backend = rid
   idmap config *:range = 1000-100000
   winbind nested groups = yes
   winbind trusted domains only = no
   winbind enum users = yes
   winbind enum groups = yes
   template homedir = /home/%D/%U
   template shell = /bin/bash
   client use spnego = yes
   client ntlmv2 auth = yes
   encrypt passwords = yes
   winbind use default domain = yes
   restrict anonymous = 2
   domain master = no
   local master = no
   preferred master = no
   os level = 0
   winbind refresh tickets = yes

[homes]
   comment = Home Directories
   browseable = no
   read only = yes
   create mask = 0700
   directory mask = 0700
   valid users = %S

[netlogon]
   comment = Network Logon Service
   path = /home/samba/netlogon
   guest ok = yes
   read only = yes

[profiles]
   comment = Users profiles
   path = /home/samba/profiles
   guest ok = no
   browseable = no
   create mask = 0600
   directory mask = 0700

[printers]
   comment = All Printers
   browseable = no
   path = /var/spool/samba
   printable = yes
   guest ok = no
   read only = yes
   create mask = 0700

[print$]
   comment = Printer Drivers
   path = /var/lib/samba/printers
   browseable = yes
   read only = yes
   guest ok = no
;   write list = root, @lpadmin

EOT

echo "Backing up nsswitch.conf..."
FILE="/etc/nsswitch.conf"
touch $FILE
mv $FILE $FILE.backup$DATE

echo "Writing new nsswitch..."
/bin/cat <<EOT >> $FILE
passwd:         compat winbind
group:          compat winbind
shadow:         compat

hosts:          files dns
networks:       files

protocols:      db files
services:       db files
ethers:         db files
rpc:            db files

netgroup:       nis

EOT


echo "Backing up hosts..."
FILE="/etc/hosts"
touch $FILE
mv $FILE $FILE.backup$DATE

echo "Writing new nsswitch..."
/bin/cat <<EOT >> $FILE

127.0.0.1    localhost
127.0.1.1    $HOSTNAME.$DOMAIN_L.$TLD_L $HOSTNAME

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
ff02::3 ip6-allhosts

EOT

echo "Joining domain..."
if net ads join -U $USERNAME%$PASSWORD; then
	echo "Domain join successful."
	else
		echo "Failed to join $REALM. Exiting"
		exit 1
	fi

# This gets the time from your DC. If you have a different time server, change it here.
#  (But if the DC can serve the time, then /shrug. Needed for Kerberos auth.
echo "Syncing NTP..."
ntpd -s $REALM_L.$DOMAIN_L.$TLD_L

# Set the local time
export TZ=$TIMEZONE
# Restart cron after local TZ change
service cron restart

# Restart winbind and samba. Fails over to unmasked samba for older (pre-systemd/upstart).
echo "Restarting samba."
service winbind restart; service nmbd restart; service smbd restart; service samba-ad-dc restart || service winbind restart; service samba restart

echo "Refreshing domain users and accounts..."
if
	wbinfo -u &>/dev/null && \
	wbinfo -g &>/dev/null && \
	getent group &>/dev/null && \
	getent passwd &>/dev/null;
	then
		echo "Synced successfully."
	else
		echo "Sync failed."
	fi

echo "Appending pam.d/common-account..."
if
	grep -q -F 'session    required    pam_mkhomedir.so skel=/etc/skel   umask=0022' \
		/etc/pam.d/common-account || \
		echo 'session    required    pam_mkhomedir.so skel=/etc/skel   umask=0022' \
		>> /etc/pam.d/common-account && \
		DEBIAN_FRONTEND=noninteractive pam-auth-update --force ;
	then
		echo "Updated pam settings."
	else
		echo "Pam update failed."
	fi

# Checks to make sure we haven't already added this group to sudoers
#   to avoid duplicates
if [ -z "$SUDOGROUP" ]; then
	echo "Skipping sudo group add."
	else
		grep -q -F "%$SUDOGROUP   ALL=(ALL:ALL) ALL" /etc/sudoers  || echo "%$SUDOGROUP   ALL=(ALL:ALL) ALL" >> /etc/sudoers
	fi

if [ -z "$SSHGROUPS" ]; then
        echo "Skipping SSH group restriction. No Groups defined."
        else
                cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup$DATE
                if grep -q AllowGroups /etc/ssh/sshd_config; then
                        sed -i "/^AllowGroups/ s/$/ $SSHGROUPS/" /etc/ssh/sshd_config
                else
                        echo "AllowGroups $SSHGROUPS" >> /etc/ssh/sshd_config
                fi
		service ssh restart
        fi


# Install ansible in here
if [ $ANSIBLE="yes" ]; then
	echo "Attempting to install Ansible..."
	if apt-cache show ansible &>/dev/null; then
		apt-get install ansible sshpass aptitude -y -q &>/dev/null|| \
			(echo "Ansible package was found, but could not be installed." && exit 1)
		echo "Ansible installed."
		else
			# If ansible not in repo, get it from github.
			echo "Ansible installation from repository failed, installing via git..."
			apt-get install git sshpass aptitude -y -q &>/dev/null || (echo "Could not install ansible" && exit 1)
			echo "Cloning ansible..."
			git clone git://github.com/ansible/ansible.git --recursive /sbin/ansible &>/dev/null
			source /sbin/ansible/hacking/env-setup
			echo "Succeeded."
		fi
    	else
	echo "Skipping Ansible install..."
	fi
# End Ansible install block

echo "Domain join complete, exiting."
exit 0
