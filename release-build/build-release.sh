#!/bin/bash

SCRIPT="$(readlink --canonicalize-existing "$0")"
SCRIPTPATH="$(dirname "${SCRIPT}")"
SCRIPTNAME=${SCRIPT##*/}
REPOPATH=${SCRIPTPATH%/*}

usage () {
    echo "Usage: ${SCRIPTNAME} [-noreg] [-repack] [-tag TAG] MODEL VERSION [EXTRA]"
    echo
    echo "  -noreg    skip regression testing"
    echo "  -repack   don't copy new stuff, redo cor and mcs, make new 7z"
    echo "  -tag TAG  TAG defaults to the 6 first characters of the branch, use"
    echo "            this for setting something like 'release-0.95'"
    echo "  MODEL     one of mega65r[23456], nexys4ddr-widget, mega65r5_6"
    echo "  VERSION   version string to put before the hash into the core version"
    echo "            maximum 31 chars. The string HASH will be replaced by the"
    echo "            hash of the build."
    echo "            The value JENKINSGEN will auto generate this text from"
    echo "            environ 'JENKINS#NUM BRANCH HASH'"
    echo "  EXTRA     file to put into the mega65 cor for fdisk population"
    echo "            (default is everything in sdcard-files)"
    echo
    echo "Example: ${SCRIPTNAME} mega65r5 'Experimental Build HASH'"
    echo
    if [[ "x$1" != "x" ]]; then
        echo $1
        echo
    fi
    exit 1
}

# check if we are in jenkins environment
if [[ -n ${JENKINS_SERVER_COOKIE} ]]; then
    BIT2COR=${SCRIPTPATH}/mega65-tools/bin/bit2core
    BIT2MCS=${SCRIPTPATH}/mega65-tools/bin/bit2mcs
    REGTEST=${SCRIPTPATH}/mega65-tools/src/tests/regression-test.sh
else
    BIT2COR=bit2core
    BIT2MCS=bit2mcs
    # tools on the same level as the mega65-core repo
    REGTEST=${REPOPATH}/../mega65-tools/src/tests/regression-test.sh
fi

rom_first () {
    for file in $@; do
        if [[ ${file##*/} = "MEGA65.ROM" ]]; then
            echo ${file}
        fi
    done
    for file in $@; do
        if [[ ${file##*/} = "FREEZER.M65" ]]; then
            echo ${file}
        fi
    done
    for file in $@; do
        if [[ ${file##*/} != "MEGA65.ROM" && ${file##*/} != "FREEZER.M65" ]]; then
            echo ${file}
        fi
    done
}

TAG="NULL"
REPACK=0
NOREG=0
while [[ $# -gt 2 && $1 =~ ^-.+ ]]; do
    if [[ $1 == "-noreg" ]]; then
        NOREG=1
    elif [[ $1 == "-repack" ]]; then
        NOREG=1
        REPACK=1
    elif [[ $1 == "-tag" ]]; then
        shift
        TAG=$1
    else
        usage "unknown option $1"
    fi
    shift
done

if [[ $# -lt 2 ]]; then
    usage
fi

MODEL=$1
VERSION=$2
shift 2
EXTRA_FILES=""
RM_HASROM=""
ROM_FILE=""
for file in $@; do
    if [[ ! -r ${file} ]]; then
        usage "extra file is unreadable: ${file}"
    elif [[ ${file##*/} = "MEGA65.ROM" ]]; then
        ROM_FILE=${file}
    else
        EXTRA_FILES="${EXTRA_FILES} ${file}"
    fi
done

BITMODEL=${MODEL}
MODELRENAME=0
if [[ ${MODEL} = "mega65r3" ]]; then
    RM_TARGET="MEGA65R3 boards -- DevKit, MEGA65 R3 and R3a (Artix A7 200T FPGA)"
elif [[ ${MODEL} = "mega65r4" ]]; then
    RM_TARGET="MEGA65R4 boards -- MEGA65 R4 (Artix A7 200T FPGA)"
elif [[ ${MODEL} = "mega65r5" ]]; then
    RM_TARGET="MEGA65R5 boards -- MEGA65 R5 (Artix A7 200T FPGA)"
elif [[ ${MODEL} = "mega65r6" ]]; then
    RM_TARGET="MEGA65R6 boards -- MEGA65 R6 (Artix A7 200T FPGA)"
elif [[ ${MODEL} = "mega65r5_6" ]]; then
    # build r5 core package using r6 bitstream
    RM_TARGET="MEGA65R5 boards -- MEGA65 R5 (Artix A7 200T FPGA)"
    MODEL="mega65r5"
    BITMODEL="mega65r6"
    MODELRENAME=1
elif [[ ${MODEL} = "mega65r2" ]]; then
    RM_TARGET="MEGA65R2 boards -- Limited Testkit (Artix A7 100T FPGA)"
elif [[ ${MODEL} = "nexys4ddr-widget" ]]; then
    RM_TARGET="Nexys4DDR boards -- Nexys4DDR, NexysA7 (Artix A7 100T FPGA)"
else
    usage "unknown model ${MODEL}"
fi

# we always pack the latest bitstream
BITPATH=$( ls -1 --sort time ${REPOPATH}/bin/${BITMODEL}*.bit | head -1 )
BITPATHBASE=${BITPATH%.bit}
BITNAME=${BITPATH##*/}
BITBASE=${BITNAME%.bit}
HASH=${BITBASE##*-}

if [[ -z ${BITPATH} ]]; then
    echo
    echo "Failed to find bitstream!"
    echo
    exit 1
fi
echo
echo "Bitstream found: ${BITNAME}"
echo
# hack for packaging r6 bitstreams as r5 cores
if [[ ${MODELRENAME} ]]; then
    BITBASE=${MODEL}-${BITBASE#*-}
    echo "NOTE: packaging ${BITMODEL} COR as ${BITBASE} using model ${MODEL} instead!"
    echo
fi

# determine branch
if [[ -n ${JENKINS_SERVER_COOKIE} ]]; then
    BRANCH=${BRANCH_NAME:0:6}
    if [[ ${VERSION} = "JENKINSGEN" ]]; then
        VERSION="JENKINS#${BUILD_NUMBER} ${BRANCH} ${HASH}"
    fi
    PKGNAME=${MODEL}-${BRANCH}-${BUILD_NUMBER}-${HASH}
else
    if [[ ${TAG} == "NULL" ]]; then
        BRANCH=`git rev-parse --abbrev-ref HEAD`
        BRANCH=${BRANCH:0:6}
    else
        BRANCH=${TAG}
    fi
    PKGNAME=${MODEL}-${BRANCH}-${HASH}
    VERSION=${VERSION/HASH/$HASH}
fi

PKGBASE=${SCRIPTPATH}/pkg
PKGPATH=${PKGBASE}/${PKGNAME}
if [[ ${REPACK} -eq 0 ]]; then
    echo "Cleaning ${PKGPATH}"
    echo
    rm -rvf ${PKGPATH}
fi

if [[ ${ROM_FILE} != "" ]]; then
    RM_HASROM="
This package also contains a ROM, which is included in the COR for automatic population
and can also be found in \`sdcard-files\`.
"
fi

for dir in ${PKGPATH}/log ${PKGPATH}/sdcard-files ${PKGPATH}/extra ${PKGPATH}/flasher; do
    if [[ ! -d ${dir} ]]; then
        mkdir -p ${dir}
    fi
done

# put text files into package path
echo "Creating info files from templates"
echo
for txtfile in README.md Changelog.md; do
    echo ".. ${txtfile}"
    ( RM_TARGET=${RM_TARGET} envsubst < ${SCRIPTPATH}/${txtfile} > ${PKGPATH}/${txtfile} )
done

UNSAFE=0

if [[ ${REPACK} -eq 0 ]]; then
    echo "Copying build files"
    echo
    cp ${REPOPATH}/bin/HICKUP.M65 ${PKGPATH}/extra/
    if [[ ${ROM_FILE} != "" ]]; then
        cp ${ROM_FILE} ${PKGPATH}/sdcard-files/
    fi
    cp ${REPOPATH}/sdcard-files/* ${PKGPATH}/sdcard-files/
    cp ${REPOPATH}/src/utilities/mflash.prg ${PKGPATH}/flasher
    cp ${REPOPATH}/src/utilities/upgrade0.prg ${PKGPATH}/flasher

    cp ${BITPATH} ${PKGPATH}/${BITBASE}.bit
    cp ${BITPATHBASE}.log ${PKGPATH}/log/
    cp ${BITPATHBASE}.timing.txt ${PKGPATH}/log/
    VIOLATIONS=$( grep -c VIOL ${BITPATHBASE}.timing.txt )
    if [[ $VIOLATIONS -gt 0 ]]; then
        touch ${PKGPATH}/WARNING_${VIOLATIONS}_TIMING_VIOLATIONS
        UNSAFE=1
    fi
fi

# do regression tests
if [[ ${NOREG} -eq 1 ]]; then
    echo "Skipping regression tests"
    if [[ ${REPACK} -eq 0 ]]; then
        touch ${PKGPATH}/WARNING_NO_TESTS_COULD_BE_EXECUTED
        UNSAFE=1
    fi
else
    echo "Starting regression tests"
    ${REGTEST} ${BITPATH} ${PKGPATH}/log/
    if [[ $? -ne 0 ]]; then
        touch ${PKGPATH}/WARNING_TESTS_HAVE_FAILED_SEE_LOGS
        UNSAFE=1
    fi
    echo "done"
fi
echo

if [[ ${UNSAFE} -eq 1 ]]; then
    touch ${PKGPATH}/ATTENTION_THIS_COULD_BRICK_YOUR_MEGA65
    # also replace JENKINS# prefix in version with UNSAFE#
    if [[ ${VERSION:0:8} = "JENKINS#" ]]; then
        VERSION="UNSAFE#${VERSION:8}"
    fi
fi

echo "Building COR/MCS"
echo
if [[ ${MODEL} == "nexys4ddr-widget" ]]; then
    ${BIT2COR} nexys4ddrwidget ${PKGPATH}/${BITBASE}.bit MEGA65 "${VERSION:0:31}" ${PKGPATH}/${BITBASE}.cor
elif [[ ${MODEL} == "mega65r2" ]]; then
    ${BIT2COR} mega65r2 ${PKGPATH}/${BITBASE}.bit MEGA65 "${VERSION:0:31}" ${PKGPATH}/${BITBASE}.cor
else
    ${BIT2COR} ${MODEL} ${PKGPATH}/${BITBASE}.bit MEGA65 "${VERSION:0:31}" ${PKGPATH}/${BITBASE}.cor $( rom_first ${PKGPATH}/sdcard-files/* ) ${EXTRA_FILES}
fi
${BIT2MCS} ${PKGPATH}/${BITBASE}.cor ${PKGPATH}/${BITBASE}.mcs 0

if [[ -n ${JENKINS_SERVER_COOKIE} ]]; then
    ARCFILE=${PKGBASE}/${MODEL}-${BRANCH}-build-${BUILD_NUMBER}.7z
else
    ARCFILE=${PKGBASE}/${MODEL}-${BRANCH}-${HASH}.7z
fi
if [[ -e ${ARCFILE} ]]; then
    rm -f ${ARCFILE}
fi

# 7z will only put the relative paths between ARCFILE and PKGPATH inside the archive. smart!
7z a ${ARCFILE} ${PKGPATH}

