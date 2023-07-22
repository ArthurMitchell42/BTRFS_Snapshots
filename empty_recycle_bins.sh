#!/bin/bash
#==============================================================================
# Script that empties the Samba recycle bins, manually or schedualed by cron
#
# Generated file to automatically snapshot defined shares
#
# Copyleft 2023 by Arthur Mitchell
#==============================================================================
{% for s in shared_folders %}
{% if s.bindays != '0' %}
# Share: {{s.name}}
if [ -d {{s.loc}}/{{s.name}}/.recycle ]; then
  find {{s.loc}}/{{s.name}}/.recycle -daystart -mtime +{{s.bindays}} -exec rm -Rfd {} \;
  find {{s.loc}}/{{s.name}}/.recycle -empty -type d -delete
fi
{% endif %}
{% endfor %}

