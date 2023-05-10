#!/bin/bash

SCRIPT="$(readlink --canonicalize-existing "$0")"
SCRIPTPATH="$(dirname "${SCRIPT}")"
SCRIPTNAME=${SCRIPT##*/}
REPOPATH=${SCRIPTPATH%/*}

usage () {
    echo "Usage: ${SCRIPTNAME} [-noreg] [-repack] MODEL VERSION [EXTRA]"
    echo
    echo "  -noreg   skip regression testing"
    echo "  -repack  don't copy new stuff, redo cor and mcs, make new 7z"
    echo "  MODEL    one of mega65r3, mega65r2, nexys4ddr-widget"
    echo "  VERSION  version string to put before the hash into the core version"
    echo "           maximum 31 chars. The string HASH will be replaced by the"
    echo "           hash of the build."
    echo "           The value JENKINSGEN will auto generate this text from"
    echo "           environ 'JENKINS#NUM BRANCH HASH'"
    echo "  EXTRA    file to put into the mega65r3 cor for fdisk population"
    echo "           (default is everything in sdcard-files)"
    echo
    echo "Example: ${SCRIPTNAME} mega65r3 'Experimental Build HASH'"
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

REPACK=0
NOREG=0
while [[ $# -gt 2 && $1 =~ ^-.+ ]]; do
    if [[ $1 == "-noreg" ]]; then
        NOREG=1
    elif [[ $1 == "-repack" ]]; then
        NOREG=1
        REPACK=1
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
EXTRA_FILES="$@"
for file in ${EXTRA_FILES}; do
    if [[ ! -r ${file} ]]; then
        usage "extra file is unreadable: ${file}"
    fi
done

if [[ ${MODEL} = "mega65r3" ]]; then
    RM_TARGET="MEGA65R3 boards -- DevKit, MEGA65 R3 and R3a (Artix A7 200T FPGA)"
elif [[ ${MODEL} = "mega65r4" ]]; then
    RM_TARGET="MEGA65R4 boards -- MEGA65 R4 (Artix A7 200T FPGA)"
elif [[ ${MODEL} = "mega65r2" ]]; then
    RM_TARGET="MEGA65R2 boards -- Limited Testkit (Artix A7 100T FPGA)"
elif [[ ${MODEL} = "nexys4ddr-widget" ]]; then
    RM_TARGET="Nexys4DDR boards -- Nexys4DDR, NexysA7 (Artix A7 100T FPGA)"
else
    usage "unknown model ${MODEL}"
fi

# we always pack the latest bitstream
BITPATH=$( ls -1 --sort time ${REPOPATH}/bin/${MODEL}*.bit | head -1 )
BITNAME=${BITPATH##*/}
BITBASE=${BITNAME%.bit}
HASH=${BITBASE##*-}

echo
echo "Bitstream found: ${BITNAME}"
echo

# determine branch
if [[ -n ${JENKINS_SERVER_COOKIE} ]]; then
    BRANCH=${BRANCH_NAME:0:6}
    if [[ ${VERSION} = "JENKINSGEN" ]]; then
        VERSION="JENKINS#${BUILD_NUMBER} ${BRANCH} ${HASH}"
    fi
    PKGNAME=${MODEL}-${BRANCH}-${BUILD_NUMBER}-${HASH}
else
    BRANCH=`git rev-parse --abbrev-ref HEAD`
    BRANCH=${BRANCH:0:6}
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
    cp ${REPOPATH}/sdcard-files/* ${PKGPATH}/sdcard-files/
    cp ${REPOPATH}/src/utilities/mflash200.prg ${PKGPATH}/flasher
    cp ${REPOPATH}/src/utilities/upgrade0.prg ${PKGPATH}/flasher

    cp ${BITPATH} ${PKGPATH}/
    cp ${BITPATH%.bit}.log ${PKGPATH}/log/
    cp ${BITPATH%.bit}.timing.txt ${PKGPATH}/log/
    VIOLATIONS=$( grep -c VIOL ${BITPATH%.bit}.timing.txt )
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
    ${BIT2COR} nexys4ddrwidget ${PKGPATH}/${BITNAME} MEGA65 "${VERSION:0:31}" ${PKGPATH}/${BITBASE}.cor
elif [[ ${MODEL} == "mega65r2" ]]; then
    ${BIT2COR} mega65r2 ${PKGPATH}/${BITNAME} MEGA65 "${VERSION:0:31}" ${PKGPATH}/${BITBASE}.cor
else
    ${BIT2COR} ${MODEL} ${PKGPATH}/${BITNAME} MEGA65 "${VERSION:0:31}" ${PKGPATH}/${BITBASE}.cor ${EXTRA_FILES} ${PKGPATH}/sdcard-files/*
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

