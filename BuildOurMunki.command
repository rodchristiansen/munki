#!/bin/sh

rm -rf /Users/admin/code
cp -r /Users/admin/Documents/Development/Munki/code /Users/admin/

/Users/admin/code/tools/make_munki_mpkg.sh -S "Developer ID Application: Example Organisation (TEAMID0000)" -s "Developer ID Installer: Example Organisation (TEAMID0000)"

rm -rf /Users/admin/code