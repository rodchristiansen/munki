#!/bin/bash

cd $HOME/DevOps/Munki/packages/MunkiTools/

$HOME/DevOps/Munki/packages/MunkiTools/code/tools/make_munki_mpkg.sh \
    -s "Developer ID Installer: Emily Carr University of Art and Design (7TF6CSP83S)" \
    -S "Developer ID Application: Emily Carr University of Art and Design (7TF6CSP83S)" \
    -n "Emily Carr University of Art and Design"