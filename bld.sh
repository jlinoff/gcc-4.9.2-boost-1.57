#!/bin/bash
#
# Date: 2014-11-05
#
# This downloads, builds and installs the gcc-4.9.2 compiler and
# boost-1.57. It was also build tcmalloc-2.2.90 on linux but not Mac
# OS. It handles the dependent packages like gmp-6.0.0a, mpfr-3.1.2,
# mpc-1.0.2, ppl-1.1, cloog-0.18.0 and binutils-2.24.
#
# The languages supported are: c, c++ and go.
#
# To install gcc-4.9.2 in ~/tmp/gcc-4.9.2/rtf/bin you would run this
# script as follows:
#
#    % # Install in ~/tmp/gcc-4.9.2/rtf/bin
#    % bld.sh ~/tmp/gcc-4.9.2 2>&1 | tee bld.log
#
# If you do not specify a directory, then it will install in the
# current directory which means that following command will also
# install in ~/tmp/gcc-4.9.2/rtf/bin:
#
#    % # Install in ~/tmp/gcc-4.9.2/rtf/bin
#    % mkdir -p ~/tmp/gcc-4.9.2
#    % cd ~/tmp/gcc-4.9.2
#    % bld.sh 2>&1 | tee bld.log
#
# This script creates 4 subdirectories:
#
#    Directory  Description
#    =========  ==================================================
#    archives   This is where the package archives are downloaded.
#    src        This is where the package source is located.
#    bld        This is where the packages are built from source.
#    rtf        This is where the packages are installed.
#
# When the build is complete you can safely remove the archives, bld
# and src directory trees to save disk space.
#
# Copyright (C) 2014 Joe Linoff
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation files
# (the "Software"), to deal in the Software without restriction,
# including without limitation the rights to use, copy, modify, merge,
# publish, distribute, sublicense, and/or sell copies of the Software,
# and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
# BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
# ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# ================================================================
# Trim a string, remove internal spaces, convert to lower case.
# ================================================================
function get-platform-trim {
    local s=$(echo "$1" | tr -d '[ \t]' | tr 'A-Z' 'a-z')
    echo $s
}

# ================================================================
# Get the platform root name.
# ================================================================
function get-platform-root
{
    if which uname >/dev/null 2>&1 ; then
        # Greg Moeller reported that the original code didn't
        # work because the -o option is not available on solaris.
        # I modified the script to correctly identify that
        # case and recover by using the -s option.
        if uname -o >/dev/null 2>&1 ; then
            # Linux distro
            uname -o | tr 'A-Z' 'a-z'
        elif uname -s >/dev/null 2>&1 ; then
            # Solaris variant
            uname -s | tr 'A-Z' 'a-z'
        else
            echo "unkown"
        fi
    else
        echo "unkown"
    fi
}

# ================================================================
# Get the platform identifier.
#
# The format of the output is:
#   <plat>-<dist>-<ver>-<arch>
#   ^      ^      ^     ^
#   |      |      |     +----- architecture: x86_64, i86pc, etc.
#   |      |      +----------- version: 5.5, 6.4, 10.9, etc.
#   |      +------------------ distribution: centos, rhel, nexenta, darwin
#   +------------------------- platform: linux, sunos, macos
#
# ================================================================
function get-platform
{
    local plat=$(get-platform-root)
    case "$plat" in
        "gnu/linux")
            d=$(get-platform-trim "$(lsb_release -i)" | awk -F: '{print $2;}')
            r=$(get-platform-trim "$(lsb_release -r)" | awk -F: '{print $2;}')
            m=$(get-platform-trim "$(uname -m)")
            if [[ "$d" == "redhatenterprise"* ]] ; then
                # Need a little help for Red Hat because
                # they don't make the minor version obvious.
                d="rhel_${d:16}"  # keep the tail (e.g., es or client)
                x=$(get-platform-trim "$(lsb_release -c)" | \
                    awk -F: '{print $2;}' | \
                    sed -e 's/[^0-9]//g')
                r="$r.$x"
            fi
            echo "linux-$d-$r-$m"
            ;;
        "cygwin")
            x=$(get-platform-trim "$(uname)")
            echo "linux-$x"
            ;;
        "sunos")
            d=$(get-platform-trim "$(uname -v)")
            r=$(get-platform-trim "$(uname -r)")
            m=$(get-platform-trim "$(uname -m)")
            echo "sunos-$d-$r-$m"
            ;;
        "darwin")
            d=$(get-platform-trim "$(uname -s)")
            r=$(get-platform-trim "$(uname -r)")
            m=$(get-platform-trim "$(uname -m)")
            echo "macos-$d-$r-$m"
            ;;
        "unknown")
            echo "unk-unk-unk-unk"
            ;;
        *)
            echo "$plat-unk-unk-unk"
            ;;
    esac
}

# ================================================================
# Command header
# Usage  : docmd_hdr $ar $*
# Example: docmd_hdr $ar <args>
# ================================================================
function docmd_hdr {
    local ar=$1
    shift
    local cmd=($*)
    echo 
    echo " # ================================================================"
    if [[ "$ar" != "" ]] ; then
        echo " # Archive: $ar"
    fi
    echo " # PWD: "$(pwd)
    echo " # CMD: "${cmd[@]}
    echo " # ================================================================"
}    

# ================================================================
# Execute command with decorations and status testing.
# Usage  : docmd $ar <cmd>
# Example: docmd $ar ls -l
# ================================================================
function docmd {
    docmd_hdr $*
    shift
    local cmd=($*)
    ${cmd[@]}
    local st=$?
    echo "STATUS = $st"
    if (( $st != 0 )) ; then
        exit $st;
    fi
}

# ================================================================
# Report an error and exit.
# Usage  : doerr <line1> [<line2> .. <line(n)>]
# Example: doerr "line 1 msg"
# Example: doerr "line 1 msg" "line 2 msg"
# ================================================================
function doerr {
    local prefix="ERROR: "
    for ln in "$@" ; do
        echo "${prefix}${ln}"
        prefix="       "
    done
    exit 1
}

# ================================================================
# Extract archive information.
# Usage  : ard=( $(extract-ar-info $ar) )
# Example: ard=( $(extract-ar-info $ar) )
#          fn=${ard[1]}
#          ext=${ard[2]}
#          d=${ard[3]}
# ================================================================
function extract-ar-info {
    local ar=$1
    local fn=$(basename $ar)
    local ext=$(echo $fn | awk -F. '{print $NF}')
    local d=${fn%.*tar.$ext}
    echo $ar
    echo $fn
    echo $ext
    echo $d
}

# ================================================================
# Print a banner for a new section.
# Usage  : banner STEP $ar
# Example: banner "DOWNLOAD" $ar
# Example: banner "BUILD" $ar
# ================================================================
function banner {
    local step=$1
    local ard=( $(extract-ar-info $2) )
    local ar=${ard[0]}
    local fn=${ard[1]}
    local ext=${ard[2]}
    local d=${ard[3]}
    echo
    echo '# ================================================================'
    echo "# Step   : $step"
    echo "# Archive: $ar"
    echo "# File   : $fn"
    echo "# Ext    : $ext"
    echo "# Dir    : $d"
    echo '# ================================================================'
}

# ================================================================
# Make a set of directories
# Usage  : mkdirs <dir1> [<dir2> .. <dir(n)>]
# Example: mkdirs foo bar spam spam/foo/bar
# ================================================================
function mkdirs {
    local ds=($*)
    for d in ${ds[@]} ; do
        if [ ! -d $d ] ; then
            mkdir -p $d
        fi
    done
}

# ================================================================
# Check the current platform to see if it is in the tested list,
# if it isn't, then issue a warning.
# It doesn't work on CentOS 5.x.
# It doesn't work on Mac OS X 10.9 (Maverick) but is close.
# ================================================================
function check-platform
{
    local plat=$(get-platform)
    local tested_plats=(
        'linux-centos-6.5-x86_64'
	'macos-darwin-13.4.0-x86_64'
    )
    local plat_found=0

    echo "PLATFORM: $plat"
    for tested_plat in ${tested_plats[@]} ; do
        if [[ "$plat" == "$tested_plat" ]] ; then
            plat_found=1
            break
        fi
    done
    if (( $plat_found == 0 )) ; then
        echo "WARNING: This platform ($plat) has not been tested."
    fi
}

# ================================================================
# my-readlink <dir>
# Some platforms (like darwin) do not support "readlink -f".
# This function checks to see if readlink -f is available,
# if it isn't then it uses a more POSIX compliant approach.
# ================================================================
function my-readlink
{
    # First make sure that the command works.
    readlink -f "$1" 1>/dev/null 2>/dev/null
    local st=$?
    if (( $st )) ; then
        # If readlink didn't work then this may be a platform
        # like Mac OS X.
        local abspath="$(cd $(dirname .); pwd)"
    else
        local abspath=$(readlink -f "$1" 2>/dev/null)
    fi
    echo "$abspath"
}

# ================================================================
# DATA
# ================================================================
# List of archives
# The order is important.
ARS=(
    http://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.14.tar.gz
    https://gmplib.org/download/gmp/gmp-6.0.0a.tar.bz2
    http://www.mpfr.org/mpfr-current/mpfr-3.1.2.tar.bz2
    http://www.multiprecision.org/mpc/download/mpc-1.0.2.tar.gz
    http://bugseng.com/products/ppl/download/ftp/releases/1.1/ppl-1.1.tar.bz2
    http://www.bastoul.net/cloog/pages/download/cloog-0.18.1.tar.gz
    http://ftp.gnu.org/gnu/gcc/gcc-4.9.2/gcc-4.9.2.tar.bz2
    http://ftp.gnu.org/gnu/binutils/binutils-2.24.tar.bz2
    http://sourceforge.net/projects/boost/files/boost/1.57.0/boost_1_57_0.tar.bz2
    https://googledrive.com/host/0B6NtGsLhIcf7MWxMMF9JdTN3UVk/gperftools-2.2.90.tar.gz

    #
    # Why glibc is disabled (for now).
    #
    # glibc does not work on CentOS because the versions of the shared
    # libraries we are building are not compatiable with installed
    # shared libraries.
    #
    # This is the run-time error: ELF file OS ABI invalid that I see
    # when I try to run binaries compiled with the local glibc-2.15.
    #
    # Note that the oldest supported ABI for glibc-2.15 is 2.2. The
    # CentOS 5.5 ABI is 0.
    # http://ftp.gnu.org/gnu/glibc/glibc-2.15.tar.bz2
)

# ================================================================
# MAIN
# ================================================================
umask 0

check-platform

# Suggested by jeaye 2014-09-17
unset LIBRARY_PATH CPATH C_INCLUDE_PATH PKG_CONFIG_PATH CPLUS_INCLUDE_PATH INCLUDE

# Read the command line argument, if it exists.
ROOTDIR=$(my-readlink .)
if (( $# == 1 )) ; then
    ROOTDIR=$(my-readlink $1)
elif (( $# > 1 )) ; then
    doerr "too many command line arguments ($#), only zero or one is allowed" "foo"
fi

# Setup the directories.
ARDIR="$ROOTDIR/archives"
RTFDIR="$ROOTDIR/rtf"
SRCDIR="$ROOTDIR/src"
BLDDIR="$ROOTDIR/bld"
TSTDIR="$SRCDIR/LOCAL-TEST"

export PATH="${RTFDIR}/bin:${PATH}"
export LD_LIBRARY_PATH="${RTFDIR}/lib:${RTFDIR}/lib64:${LD_LIBRARY_PATH}"

echo
echo "# ================================================================"
echo '# Version    : gcc-4.9.2 2014-11-05'
echo "# RootDir    : $ROOTDIR"
echo "# ArchiveDir : $ARDIR"
echo "# RtfDir     : $RTFDIR"
echo "# SrcDir     : $SRCDIR"
echo "# BldDir     : $BLDDIR"
echo "# TstDir     : $TSTDIR"
echo "# Gcc        : "$(which gcc)
echo "# GccVersion : "$(gcc --version | head -1)
echo "# Hostname   : "$(hostname)
echo "# O/S        : "$(uname -s -r -v -m)
echo "# Date       : "$(date)
echo "# Platform   : "$(get-platform)
echo "# ================================================================"

mkdirs $ARDIR $RTFDIR $SRCDIR $BLDDIR

# ================================================================
# Download
# ================================================================
for ar in ${ARS[@]} ; do
    banner 'DOWNLOAD' $ar
    ard=( $(extract-ar-info $ar) )
    fn=${ard[1]}
    ext=${ard[2]}
    d=${ard[3]}
    if [  -f "${ARDIR}/$fn" ] ; then
        echo "INFO: already downloaded $fn"
    else
        # get
        docmd $ar wget  --no-check-certificate $ar -O "${ARDIR}/$fn"
    fi
done

# ================================================================
# Extract
# ================================================================
for ar in ${ARS[@]} ; do
    banner 'EXTRACT' $ar
    ard=( $(extract-ar-info $ar) )
    fn=${ard[1]}
    ext=${ard[2]}
    d=${ard[3]}
    sd="$SRCDIR/$d"
    if [ -d $sd ] ; then
        echo "INFO: already extracted $fn"
    else
        # unpack
        pushd $SRCDIR
        case "$ext" in
            "bz2")
                docmd $ar tar jxf ${ARDIR}/$fn
                ;;
            "gz")
                docmd $ar tar zxf ${ARDIR}/$fn
                ;;
            "tar")
                docmd $ar tar xf ${ARDIR}/$fn
                ;;
            *)
                doerr "unrecognized extension: $ext" "Can't continue."
                ;;
        esac
        popd
        if [ ! -d $sd ] ;  then
            # Some archives (like gcc-g++) overlay. We create a dummy
            # directory to avoid extracting them every time.
            mkdir -p $sd
        fi
    fi

    # special hack for gmp-6.0.0a
    if [[ $d == "gmp-6.0.0a" ]] ; then
	if [ ! -f $sd/configure ] ; then
	    sdn="$SRCDIR/gmp-6.0.0"
	    echo "INFO: fixing $sdn --> $sd"
	    docmd $sd rm -rf $sd
	    docmd $sd ln -s $sdn $sd
	fi
    fi
done

# ================================================================
# Build
# ================================================================
for ar in ${ARS[@]} ; do
    banner 'BUILD' $ar
    ard=( $(extract-ar-info $ar) )
    fn=${ard[1]}
    ext=${ard[2]}
    d=${ard[3]}
    sd="$SRCDIR/$d"
    bd="$BLDDIR/$d"
    if [ -d $bd ] ; then
        echo "INFO: already built $sd"
    else
        # Build
        regex='^gcc-g\+\+.*'
        if [[ $fn =~ $regex ]] ; then
            # Don't build/configure the gcc-g++ package explicitly because
            # it is part of the regular gcc package.
            echo "INFO: skipping $sd"
            # Dummy
            continue
        fi

        # Set the CONF_ARGS
        plat=$(get-platform)
        run_conf=1
        run_boost_bootstrap=0
        case "$d" in
            binutils-*)
                # Binutils will not compile with strict error
                # checking on so I disabled -Werror by setting
                # --disable-werror.
                CONF_ARGS=(
                    --disable-cloog-version-check
                    --disable-ppl-version-check
                    --disable-werror
                    --enable-cloog-backend=isl
                    --enable-lto
                    --enable-libssp
                    --enable-gold
                    --prefix=${RTFDIR}
                    --with-cloog=${RTFDIR}
                    --with-gmp=${RTFDIR}
                    --with-mlgmp=${RTFDIR}
                    --with-mpc=${RTFDIR}
                    --with-mpfr=${RTFDIR}
                    --with-ppl=${RTFDIR}
                    CC=${RTFDIR}/bin/gcc
                    CXX=${RTFDIR}/bin/g++
                )
                ;;

            boost_*)
                # The boost configuration scheme requires
                # that the build occur in the source directory.
                run_conf=0
                run_boost_bootstrap=1
                CONF_ARGS=(
                    --prefix=${RTFDIR}
                    --with-python=python2.7
                )
                ;;

            cloog-*)
                GMPDIR=$(ls -1d ${BLDDIR}/gmp-*)
                CONF_ARGS=(
                    --prefix=${RTFDIR}
                    --with-gmp-builddir=${GMPDIR}
                    --with-gmp=build
                )
                ;;

            gcc-*)
                # We are using a newer version of CLooG (0.18.0).
                # I have also made stack protection available
                # (similar to DEP in windows).
                CONF_ARGS=(
                    --disable-cloog-version-check
                    --disable-ppl-version-check
                    --enable-cloog-backend=isl
                    --enable-gold
                    --enable-languages='c,c++,go'
                    --enable-lto
                    --enable-libssp
                    --prefix=${RTFDIR}
                    --with-cloog=${RTFDIR}
                    --with-gmp=${RTFDIR}
                    --with-mlgmp=${RTFDIR}
                    --with-mpc=${RTFDIR}
                    --with-mpfr=${RTFDIR}
                    --with-ppl=${RTFDIR}
                )

                macplats=(
		    'macos-darwin-13.0.0-x86_64'
		    'macos-darwin-13.1.0-x86_64'
		    'macos-darwin-13.4.0-x86_64'
		)
                for macplat in ${macplats[@]} ; do
                    if [[ "$plat" == "$macplat" ]] ; then
                        # Special handling for Mac OS X 10.9.
                        # Fix the bad reference to CFBase.h in
                        # src/gcc-4.9.2/libsanitizer/asan/asan_malloc_mac.cc
                        src="$sd/libsanitizer/asan/asan_malloc_mac.cc"
                        if [ -f $src ] ; then
                            if [ ! -f $src.orig ] ; then
                                cp $src $src.orig
                                cat $src.orig |\
                            sed -e 's@#include <CoreFoundation/CFBase.h>@//#include <CoreFoundation/CFBase.h>@' >$src
                            fi
                        fi
                    fi
                done
                ;;

            glibc-*)
                CONF_ARGS=(
                    --enable-static-nss=no
                    --prefix=${RTFDIR}
                    --with-binutils=${RTFDIR}
                    --with-elf
                    CC=${RTFDIR}/bin/gcc
                    CXX=${RTFDIR}/bin/g++
                )
                ;;

            gmp-*)
                CONF_ARGS=(
                    --enable-cxx
                    --prefix=${RTFDIR}
                )
                if [[ "$plat" == "linux-cygwin_nt-6.1-wow64" ]] ; then
                    CONF_ARGS+=('--enable-static')
                    CONF_ARGS+=('--disable-shared')
                fi
                ;;

	    gperf*)
                CONF_ARGS=(
                    --prefix=${RTFDIR}
		    --enable-frame-pointers
		    --with-gnu-ld
                )
		regex='^macos-.*'
		if [[ "$plat" =~ $regex ]] ; then
		    # Skip tcmalloc (gperftools) on Mac OS X.
		    # It doesn't build properly.
		    echo "INFO: skipping $d, it doesn't build on Mac OS X"
		    run_conf=0
		    run_boost_bootstrap=0
		fi
		;;

            libiconv-*)
                CONF_ARGS=(
                    --prefix=${RTFDIR}
                )
                ;;

            mpc-*)
                CONF_ARGS=(
                    --prefix=${RTFDIR}
                    --with-gmp=${RTFDIR}
                    --with-mpfr=${RTFDIR}
                )
                if [[ "$plat" == "linux-cygwin_nt-6.1-wow64" ]] ; then
                    CONF_ARGS+=('--enable-static')
                    CONF_ARGS+=('--disable-shared')
                fi
                ;;

            mpfr-*)
                CONF_ARGS=(
                    --prefix=${RTFDIR}
                    --with-gmp=${RTFDIR}
                )
                ;;

            ppl-*)
                CONF_ARGS=(
                    --prefix=${RTFDIR}
                    --with-gmp=${RTFDIR}
                )
                if [[ "$plat" == "linux-cygwin_nt-6.1-wow64" ]] ; then
                    # Cygwin does not implement long double so I cheated.
                    CONF_ARGS+=('--enable-static')
                    CONF_ARGS+=('--disable-shared')
                fi

                # We need a special fix for the pax archive prompt.
                # Change the configure code.
                if [ ! -f "$sd/configure.orig" ] ; then
                    # Fix the configure code so that it does not use 'pax -r'.
                    # The problem with 'pax -r' is that it expects a "." input
                    # from stdin which breaks the flow.
                    cp $sd/configure{,.orig}
                    sed -e "s/am__untar='pax -r'/am__untar='tar -xf'  #am__untar='pax -r'/" \
                        $sd/configure.orig >$sd/configure
                fi

                # We need to make a special fix here
                src="$sd/src/mp_std_bits.defs.hh"
                if [ -f $src ] ; then
                    if [ ! -f $src.orig ] ; then
                        if ! grep -q '__GNU_MP_VERSION' $src ; then
                            cp $src $src.orig
                            cat $src.orig | \
                                awk \
'{ \
  if($1=="namespace" && $2 == "std") { \
    printf("// Automatically patched by bld.sh for gcc-4.9.2.\n"); \
    printf("#define tininess_before tinyness_before\n"); \
    printf("#if __GNU_MP_VERSION < 5  || (__GNU_MP_VERSION == 5 && __GNU_MP_VERSION_MINOR < 1)\n");
  } \
  print $0; \
  if($1 == "}" && $2=="//" && $3=="namespace") { \
    printf("#endif  // #if __GNU_MP_VERSION < 5  || (__GNU_MP_VERSION == 5 && __GNU_MP_VERSION_MINOR < 1)\n");
  } \
}' >$src
                        fi
                    fi
                fi
                ;;

            *)
                doerr "unrecognized package: $d"
                ;;
        esac

        mkdir -p $bd
        pushd $bd
        if (( $run_conf )) ; then
            docmd $ar $sd/configure --help
            docmd $ar $sd/configure ${CONF_ARGS[@]}
            docmd $ar make
            docmd $ar make install
        fi
        if (( $run_boost_bootstrap )) ; then
            pushd $sd
            docmd $ar which g++
            docmd $ar gcc --version
            docmd $ar $sd/bootstrap.sh --help
            docmd $ar $sd/bootstrap.sh ${CONF_ARGS[@]}
            docmd $ar ./b2 --help
            docmd $ar ./b2 --clean
            docmd $ar ./b2 --reconfigure
            docmd $ar ./b2 -a -d+2 --build-dir $bd
            docmd $ar ./b2 -d+2 --build-dir $bd install
            docmd $ar ./b2 install
            popd
        fi

        # Redo the tests if anything changed.
        if [ -d $TSTDIR ] ; then
            rm -rf $TSTDIR
        fi
        popd
    fi
done

# ================================================================
# Test
# ================================================================
if [ -d $TSTDIR ] ; then
    echo "INFO: skipping tests"
else
    docmd "MKDIR" mkdir -p $TSTDIR
    pushd $TSTDIR
    docmd "LOCAL TEST  1" which g++
    docmd "LOCAL TEST  2" which gcc
    docmd "LOCAL TEST  3" which c++
    docmd "LOCAL TEST  4" g++ --version

    # Set test environment.
    cat >setenv.sh <<EOF
export PATH="${RTFDIR}/bin:\${PATH}"
export LD_LIBRARY_PATH="${RTFDIR}/lib:${RTFDIR}/lib64:\${LD_LIBRARY_PATH}"
EOF

    # Simple aliveness test.
    cat >test1.cc <<EOF
#include <iostream>
using namespace std;
int main()
{
  cout << "IO works" << endl;
  return 0;
}
EOF
    docmd "LOCAL TEST  5" g++ -O3 -Wall -o test1.bin test1.cc
    docmd "LOCAL TEST  6" ./test1.bin

    docmd "LOCAL TEST  7" g++ -g -Wall -o test1.dbg test1.cc
    docmd "LOCAL TEST  8" ./test1.dbg

    # Simple aliveness test for boost.
    cat >test2.cc <<EOF
#include <iostream>
#include <boost/algorithm/string.hpp>
using namespace std;
using namespace boost;
int main()
{
  string s1(" hello world! ");
  cout << "value      : '" << s1 << "'" <<endl;

  to_upper(s1);
  cout << "to_upper() : '" << s1 << "'" <<endl;

  trim(s1);
  cout << "trim()     : '" << s1 << "'" <<endl;

  return 0;
}
EOF
    docmd "LOCAL TEST  9" g++ -O3 -Wall -o test2.bin test2.cc
    docmd "LOCAL TEST 10" ./test2.bin

    docmd "LOCAL TEST 11" g++ -g -Wall -o test2.dbg test2.cc
    docmd "LOCAL TEST 12" ./test2.dbg

    docmd "LOCAL TEST" ls -l 

    # Simple aliveness test for C++11.
    # Initializer lists, auto and foreach.
    cat >test3.cc <<EOF
#include <iostream>
#include <string>
#include <vector>

using namespace std;

int main()
{
  vector<int> v1 = {10, 21, 32, 43};
  vector<string> v2 = {"foo", "bar", "spam"};

  for (auto i : v1) {
    cout << "v1: " << i << endl;
  }

  for (auto i : v2) {
    cout << "v2: " << i << endl;
  }
  return 0;
}
EOF
    docmd "LOCAL TEST 13" g++ -std=c++11 -O3 -Wall -o test3.bin test3.cc
    docmd "LOCAL TEST 14" ./test3.bin

    docmd "LOCAL TEST 15" g++ -std=c++11 -g -Wall -o test3.dbg test3.cc
    docmd "LOCAL TEST 16" ./test3.dbg

    docmd "LOCAL TEST" ls -l 

    popd
fi
