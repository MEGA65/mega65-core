#!/bin/bash

SCRIPT="$(readlink --canonicalize-existing "$0")"
SCRIPTPATH="$(dirname "${SCRIPT}")"
SCRIPTNAME=${SCRIPT##*/}

cd ${SCRIPTPATH}

if [[ $1 = "prunepkg" ]]; then
    rm -rf pkg
fi

# freshly clone release prep
#echo "Removing and recloning mega65-release-prep..."
#rm -rf mega65-release-prep
#git clone https://github.com/MEGA65/mega65-release-prep.git || ( echo "failed to clone mega65-release-prep"; exit 1 )

# freshly clone tools
echo
echo "Removing and recloning mega65-tools..."
rm -rf mega65-tools
git clone https://github.com/MEGA65/mega65-tools.git || ( echo "failed to clone mega65-tools"; exit 2 )

echo
echo "Building tools..."
cd mega65-tools
make DO_SMU=1 USE_LOCAL_CC65=0 bin/m65 bin/bit2core bin/bit2mcs tests || ( echo "failed to build mega65-tools"; exit 3)
