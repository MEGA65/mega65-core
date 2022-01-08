#!/bin/bash

SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`

cd $SCRIPTPATH

# freshly clone release prep
echo "Removing and recloning mega65-release-prep..."
rm -rf mega65-release-prep
git clone https://github.com/MEGA65/mega65-release-prep.git || ( echo "failed to clone mega65-release-prep"; exit 1 )

# freshly clone tools
echo
echo "Removing and recloning mega65-tools..."
rm -rf mega65-tools
git clone https://github.com/MEGA65/mega65-tools.git || ( echo "failed to clone mega65-tools"; exit 2 )

echo
echo "Building tools..."
cd mega65-tools
make bin/bit2core bin/bit2mcs || ( echo "failed to build bit2core and bit2mcs"; exit 3)
