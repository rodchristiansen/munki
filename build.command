#!/bin/bash

cd $HOME/DevOps/Munki/packages/MunkiTools/

$HOME/DevOps/Munki/packages/MunkiTools/code/tools/make_munki_mpkg.sh \
    -s "Developer ID Installer: Example Organisation (TEAMID0000)" \
    -S "Developer ID Application: Example Organisation (TEAMID0000)" \
    -n "Example Organisation"