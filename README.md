# DebianDomainJoin
#### Script for adding any Debian member machine to an Active Directory domain.

- Should work on any Debian-based distribution (including Raspbian).
- Installs all of the necessary packages to communicate with Kerberos and Active Directory.
- Backs up Kerberos, Samba, NSSwitch, and hosts, and creates a valid domain configuration for each.
- Joins the domain using 'net'.
- Synchronizes the time with the Domain Controller using ntpd and sets the local timezone.
- Optionally adds a local/AD group to the sudoers file.
- Optionally installs Ansible and accompanying useful packages for member machine remote administration.

#### Before launching:

1. Set the timezone. Check in /usr/share/zoneinfo/ if you don't know the format.
2. Set a sudoers group. Or don't, and leave it blank. I'm a readme, not the police.
3. Mark whether or not you want Ansible installed. It's pretty cool, so I recommend it if you don't have some other management system in place.
4. Option to restrict which users can SSH into member machines by group.

#### Why use this script?

- Realmd is cool, but isn't in all standard repositories, and doesn't do a lot more than 'net ads join' does.
- A centralized script assures you that all member machines receive the same configuration.
- It permits easy expandability of features that you might want to distribute across all members.
- Even if you use a tool instead of this, it's nice to know what's going on under the hood.
