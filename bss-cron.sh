#!/bin/bash 
#=========================================================================================
# Generated file to automatically snapshot defined shares
#
{% for s in shared_folders %}
{% if s.snap == "yes" %}
#=========================================================================================
# Share: {{s.name}}
/usr/local/sbin/btrfs-share-snap.sh {{s.loc}}/{{s.name}} -v -c 7 -t daily   -m 86300 -o >> /var/log/bss-cron.log
/usr/local/sbin/btrfs-share-snap.sh {{s.loc}}/{{s.name}} -v -c 4 -t weekly  -m 604700   >> /var/log/bss-cron.log
/usr/local/sbin/btrfs-share-snap.sh {{s.loc}}/{{s.name}} -v -c 6 -t monthly -m 2419100  >> /var/log/bss-cron.log
{% endif %}

{% endfor %}
