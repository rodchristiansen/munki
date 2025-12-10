#!/bin/bash
#
# Cleanup script to remove old munkipkg from /usr/local/bin
# munkipkg is now installed to /usr/local/munki as part of the admin tools
#

OLD_MUNKIPKG="/usr/local/bin/munkipkg"

if [ -f "$OLD_MUNKIPKG" ] || [ -L "$OLD_MUNKIPKG" ]; then
    echo "Removing old munkipkg from /usr/local/bin..."
    rm -f "$OLD_MUNKIPKG"
fi

exit 0
