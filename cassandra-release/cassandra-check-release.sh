#!/bin/bash

# Parameters
# $1 staged|released
# $2 release
# $3 maven artefacts staging repo id (as specified in the repo url found in the vote email) (ignored for 'released')
#
# Example use: `./cassandra-check-release.sh staged 4.0-beta3 1224
#
# This script is very basic and experimental. I beg of you to help improve it.
#

# Fail on any error
set -euo pipefail

###################
# prerequisites

command -v wget >/dev/null 2>&1 || { echo >&2 "wget needs to be installed"; exit 1; }
command -v gpg >/dev/null 2>&1 || { echo >&2 "gpg needs to be installed"; exit 1; }
command -v sha1sum >/dev/null 2>&1 || { echo >&2 "sha1sum needs to be installed"; exit 1; }
command -v md5sum >/dev/null 2>&1 || { echo >&2 "md5sum needs to be installed"; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo >&2 "sha256sum needs to be installed"; exit 1; }
command -v sha512sum >/dev/null 2>&1 || { echo >&2 "sha512sum needs to be installed"; exit 1; }
command -v tar >/dev/null 2>&1 || { echo >&2 "tar needs to be installed"; exit 1; }
command -v docker >/dev/null 2>&1 || { echo >&2 "docker needs to be installed"; exit 1; }
(docker info >/dev/null 2>&1) || { echo >&2 "docker needs to running"; exit 1; }

( [ $# -ge 2 ] ) || { echo >&2 "Usage $0 (staged|released) version [maven_staging_repo_id]"; exit 1; }
( [ "staged" = $1 ] || [ "released" = $1 ] ) || { echo >&2 "first argument must be staged or released"; exit 1; }
if [ -z "${3:-}" ] ; then
    [ "released" == $1 ] || { echo >&2 "third argument must not be specified when first is released"; exit 1; }
    dist_url="https://dist.apache.org/repos/dist/release/cassandra/$2/"
    maven_repo_url="https://repository.apache.org/content/repositories/releases/org/apache/cassandra/cassandra-all/$2"
    debian_url="https://apache.jfrog.io/artifactory/cassandra-deb/"
    redhat_url="https://apache.jfrog.io/artifactory/cassandra-rpm/"
else
    [ "staged" == $1 ] || { echo >&2 "third argument must be specified when first is staged"; exit 1; }
    dist_url="https://dist.apache.org/repos/dist/dev/cassandra/$2/"
    maven_repo_url="https://repository.apache.org/content/repositories/orgapachecassandra-$3/org/apache/cassandra/cassandra-all/$2"
    debian_url="https://dist.apache.org/repos/dist/dev/cassandra/${2}/debian/"
    redhat_url="https://dist.apache.org/repos/dist/dev/cassandra/${2}/redhat/"
fi
(curl --output /dev/null --silent --head --fail "${dist_url}") || { echo >&2 "Not Found: ${dist_url}"; exit 1; }
(curl --output /dev/null --silent --head --fail "${maven_repo_url}") || { echo >&2 "Not found: ${maven_repo_url}"; exit 1; }

###################

release_short=${2}
# Remove -prerelease label if the release version contains "-"
if [ $(expr index "$2" "-") != 0 ]; then
    idx=$(expr index "$2" "-")
    release_short=${2:0:$((idx-1))}
fi
packaging_series="$(echo ${release_short} | cut -d '.' -f 1)$(echo ${release_short} | cut -d '.' -f 2)x"

# Use unique directory for idempotency
BASEDIR=/tmp/$2
mkdir -p ${BASEDIR}
TMPDIR=`mktemp -d -p ${BASEDIR}`
cd ${TMPDIR}

echo "Using ${TMPDIR} as staging directory"
echo "Downloading KEYS"
wget -q https://downloads.apache.org/cassandra/KEYS
echo "Downloading ${maven_repo_url}"
wget -Nqnd -e robots=off --recursive --no-parent ${maven_repo_url}
echo "Downloading ${dist_url}"
wget -Nqe robots=off --recursive --no-parent ${dist_url}
if [ -z "${3:-}" ] ; then
    mkdir dist.apache.org/repos/dist/release/cassandra/$2/{debian,redhat}
    deb_url="${debian_url}/pool/main/c/cassandra/"
    echo "Downloading ${deb_url}/*${release_short}*.deb"
    # folder structure to be trimmed by -nH --cut-dirs opt: apache.jfrog.io/artifactory/cassandra-deb//pool/main/c/cassandra
    wget -Nqe robots=off -nH --cut-dirs=7 --recursive --no-parent -A "*${release_short}*.deb" -P dist.apache.org/repos/dist/release/cassandra/$2/debian ${deb_url}
    rpm_url="${redhat_url}/${packaging_series}/"
    echo "Downloading ${rpm_url}/*${release_short}*.rpm"
    # folder structure to be trimmed by -nH --cut-dirs opt: apache.jfrog.io/artifactory/cassandra-rpm//41x/
    wget -Nqe robots=off -nH --cut-dirs=4 --recursive --no-parent -A "*${release_short}*.rpm" -P dist.apache.org/repos/dist/release/cassandra/$2/redhat ${rpm_url}
fi

echo
echo "====== CHECK RESULTS ======"
echo

gpg --import KEYS

(compgen -G "*.asc" >/dev/null) || { echo >&2 "No *.asc files found in $(pwd)"; exit 1; }
for f in *.asc ; do gpg --verify $f ; done
(compgen -G "*.pom" >/dev/null) || { echo >&2 "No *.pom files found in $(pwd)"; exit 1; }
(compgen -G "*.jar" >/dev/null) || { echo >&2 "No *.jar files found in $(pwd)"; exit 1; }
for f in *.pom *.jar *.asc ; do echo -n "sha1: " ; echo "$(cat $f.sha1) $f" | sha1sum -c ; echo -n "md5: " ; echo "$(cat $f.md5) $f" | md5sum -c ; done

cd dist.apache.org/repos/dist/*/cassandra/$2
(compgen -G "*.asc" >/dev/null) || { echo >&2 "No *.asc files found in $(pwd)"; exit 1; }
for f in *.asc ; do gpg --verify $f ; done
(compgen -G "*.gz" >/dev/null) || { echo >&2 "No *.gz files found in $(pwd)"; exit 1; }
(compgen -G "*.sha256" >/dev/null) || { echo >&2 "No *.sha256 files found in $(pwd)"; exit 1; }
(compgen -G "*.sha512" >/dev/null) || { echo >&2 "No *.sha512 files found in $(pwd)"; exit 1; }
for f in *.gz ; do echo -n "sha256: " ; echo "$(cat $f.sha256) $f" | sha256sum -c ; echo -n "sha512:" ; echo "$(cat $f.sha512) $f" | sha512sum -c ; done

echo
echo "Extracting binary.."
tar -xzf apache-cassandra-$2-src.tar.gz
echo "Extracting sources.."
tar -xzf apache-cassandra-$2-bin.tar.gz

JDKS="8"
if [[ $2 =~ [4]\. ]] ; then
    JDKS=("8" "11")
elif [[ $2 =~ [5]\. ]] ; then
    JDKS=("11" "17")
fi
echo "Testing JDKs: ${JDKS[@]}"
TIMEOUT=2160

# Create pipe used for check_output to verify expected output
mkfifo procfifo

has_failure=false
function check_output
{
    PID=$1
    shift 1
    SECONDS=0
    EXPECTED_OUTPUT="$@"
    success=false
    while read LINE ; do
        if [[ $LINE =~ "${EXPECTED_OUTPUT}" ]] ; then
            success=true
            break
        fi
    done < procfifo
    if $success ; then
        echo "OK (Took ${SECONDS}s)"
    else
        has_failure=true
        echo "FAILED (Took ${SECONDS}s)"
    fi
    if kill "$PID" && wait -f "$PID"; then
        echo "WARN: killed process ${PID} exited with zero status when it shouldn't."
    fi
}

for JDK in ${JDKS[@]} ; do

    # test source tarball build
    if [ "$JDK" == "11" ] ; then
        BUILD_OPT="-Duse.jdk11=true"
    fi

    echo -ne "\nChecking source build (JDK ${JDK})... "
    docker run -i -v `pwd`/apache-cassandra-$2-src:/apache-cassandra-$2-src openjdk:${JDK}-jdk-slim-buster timeout ${TIMEOUT} /bin/bash -c "
        ( echo 'deb http://archive.debian.org/debian buster main' > /etc/apt/sources.list;
          echo 'deb http://archive.debian.org/debian-security buster/updates main' >> /etc/apt/sources.list;
          apt -qq update;
          apt -qq install -y wget ant build-essential git python python3 procps;
          wget https://go.dev/dl/go1.24.5.linux-amd64.tar.gz;
          tar -C /usr/local -xzf go1.24.5.linux-amd64.tar.gz; ) 2>&1 >/dev/null;
        export PATH=/usr/local/openjdk-11/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/go/bin:/usr/local/go/bin;
        cd apache-cassandra-$2-src;
        ant artifacts ${BUILD_OPT:-} " &> procfifo &
    PID=$!
    check_output $PID "BUILD SUCCESSFUL"

    # test binary tarball startup
    echo -ne "\nChecking binary artefact (JDK ${JDK})... "
    docker run -i -v `pwd`/apache-cassandra-$2:/apache-cassandra-$2 openjdk:${JDK}-jdk-slim-buster timeout ${TIMEOUT} /bin/bash -c "
        ( echo 'deb http://archive.debian.org/debian buster main' > /etc/apt/sources.list;
          echo 'deb http://archive.debian.org/debian-security buster/updates main' >> /etc/apt/sources.list;
          apt -qq update;
          apt -qq install -y python python3 procps ) 2>&1 >/dev/null;
        HEAP_NEWSIZE=500m MAX_HEAP_SIZE=1g MAX_DIRECT_MEMORY_SIZE=1g apache-cassandra-$2/bin/cassandra -R -f -Dcassandra.ring_delay_ms=1000" &> procfifo &
    PID=$!
    check_output $PID "Starting listening for CQL clients on"

    # test deb package startup
    if [ "$JDK" == "8" ] ; then
        DEBIAN_IMAGE="openjdk:8-jdk-slim-buster"
    else
        DEBIAN_IMAGE="debian:bullseye-slim"
    fi

    echo -ne "\nChecking Debian package (JDK ${JDK})... "
    if [ "$JDK" == "8" ] ; then
      docker run -i -v `pwd`/debian:/debian ${DEBIAN_IMAGE} timeout ${TIMEOUT} /bin/bash -c "
          ( echo 'deb http://archive.debian.org/debian buster main' > /etc/apt/sources.list;
            echo 'deb http://archive.debian.org/debian-security buster/updates main' >> /etc/apt/sources.list;
            apt -qq update ;
            apt -qq install -y python ; # will silently fail on debian latest
            apt -qq install -y python3 procps ;
            apt -qq install -y openjdk-${JDK}-jre-headless ; # will silently fail on *jdk-slim-buster
            dpkg --ignore-depends=java7-runtime --ignore-depends=java8-runtime -i debian/*.deb ) 2>&1 >/dev/null ;
          HEAP_NEWSIZE=500m MAX_HEAP_SIZE=1g MAX_DIRECT_MEMORY_SIZE=1g cassandra -R -f -Dcassandra.ring_delay_ms=1000" &> procfifo &
    else
      docker run -i -v `pwd`/debian:/debian ${DEBIAN_IMAGE} timeout ${TIMEOUT} /bin/bash -c "
          ( apt -qq update ;
            apt -qq install -y python ; # will silently fail on debian latest
            apt -qq install -y python3 procps ;
            apt -qq install -y openjdk-${JDK}-jre-headless ; # will silently fail on *jdk-slim-buster
            dpkg --ignore-depends=java7-runtime --ignore-depends=java8-runtime -i debian/*.deb ) 2>&1 >/dev/null ;
          HEAP_NEWSIZE=500m MAX_HEAP_SIZE=1g MAX_DIRECT_MEMORY_SIZE=1g cassandra -R -f -Dcassandra.ring_delay_ms=1000" &> procfifo &
    fi
    PID=$!
    check_output $PID "Starting listening for CQL clients on"

    # test deb repository startup
    echo -ne "\nChecking Debian repository (JDK ${JDK})... "
    if [ "$JDK" == "8" ] ; then
      docker run -i ${DEBIAN_IMAGE} timeout ${TIMEOUT} /bin/bash -c "
          ( echo 'deb http://archive.debian.org/debian-security buster/updates main' >> /etc/apt/sources.list;
            echo 'deb http://archive.debian.org/debian buster main' > /etc/apt/sources.list;
            apt -qq update ;
            apt -qq install -y curl gnupg2 ;
            apt-key adv --keyserver keyserver.ubuntu.com  --recv-key E91335D77E3E87CB ;
            curl https://downloads.apache.org/cassandra/KEYS | apt-key add - ;
            apt update  ;
            echo 'deb ${debian_url} ${packaging_series} main' | tee -a /etc/apt/sources.list.d/cassandra.sources.list ;
            apt update  ;
            apt-get install -y cassandra ) 2>&1 >/dev/null ;
          HEAP_NEWSIZE=500m MAX_HEAP_SIZE=1g MAX_DIRECT_MEMORY_SIZE=1g cassandra -R -f -Dcassandra.ring_delay_ms=1000" &> procfifo &
    else
      docker run -i ${DEBIAN_IMAGE} timeout ${TIMEOUT} /bin/bash -c "
          ( apt -qq update ;
            apt -qq install -y curl gnupg2 ;
            apt-key adv --keyserver keyserver.ubuntu.com  --recv-key E91335D77E3E87CB ;
            curl https://downloads.apache.org/cassandra/KEYS | apt-key add - ;
            apt update  ;
            echo 'deb ${debian_url} ${packaging_series} main' | tee -a /etc/apt/sources.list.d/cassandra.sources.list ;
            apt update  ;
            apt-get install -y cassandra ) 2>&1 >/dev/null ;
          HEAP_NEWSIZE=500m MAX_HEAP_SIZE=1g MAX_DIRECT_MEMORY_SIZE=1g cassandra -R -f -Dcassandra.ring_delay_ms=1000" &> procfifo &
    fi
    PID=$!
    check_output $PID "Starting listening for CQL clients on"

    # test red hat startup for different dists
    if [ "$JDK" == "8" ] ; then
        JDK_RH="java-1.8.0-openjdk"
    else
        JDK_RH="java-${JDK}-openjdk-devel"
    fi

    RH_DISTS="almalinux"
    if ! [[ $2 =~ [23]\. ]] ; then
        RH_DISTS=("almalinux" "noboolean")
    fi

    for RH_DIST in ${RH_DISTS[@]} ; do

        NOBOOLEAN_REPO=""
        if [ "$RH_DIST" == "noboolean" ] ; then
            NOBOOLEAN_REPO="/noboolean"
        fi

        REPO_VERSION=""
        if [ "released" == "$1" ] ; then
            REPO_VERSION="${packaging_series}"
        fi

        # test rpm package startup
        echo -ne "\nChecking Redhat package (${RH_DIST} JDK ${JDK})... "
        docker run -i -v `pwd`/redhat${NOBOOLEAN_REPO}:/redhat almalinux timeout ${TIMEOUT} /bin/bash -c "
            ( yum install -y  procps-ng python3-pip;
            yum install -y ${JDK_RH} ;
            rpm -i --nodeps redhat/*.rpm ) 2>&1 >/dev/null ;
            HEAP_NEWSIZE=500m MAX_HEAP_SIZE=1g MAX_DIRECT_MEMORY_SIZE=1g cassandra -R -f -Dcassandra.ring_delay_ms=1000" &> procfifo &
        PID=$!
        check_output $PID "Starting listening for CQL clients on"

        # test redhat repository startup
        echo -ne "\nChecking Redhat repository (${RH_DIST} JDK ${JDK})... "
        # yum repo installation failing due to a legacy (SHA1) third-party sig in our KEYS file, hence use of update-crypto-policies. Impacts all rhel9+ users.
        docker run -i  almalinux timeout ${TIMEOUT} /bin/bash -c "(
            echo '[cassandra]' >> /etc/yum.repos.d/cassandra.repo ;
            echo 'name=Apache Cassandra' >> /etc/yum.repos.d/cassandra.repo ;
            echo 'baseurl=${redhat_url}${REPO_VERSION}${NOBOOLEAN_REPO}' >> /etc/yum.repos.d/cassandra.repo ;
            echo 'gpgcheck=1' >> /etc/yum.repos.d/cassandra.repo ;
            echo 'repo_gpgcheck=1' >> /etc/yum.repos.d/cassandra.repo ;
            echo 'gpgkey=https://downloads.apache.org/cassandra/KEYS' >> /etc/yum.repos.d/cassandra.repo ;

            update-crypto-policies --set LEGACY ;

            yum install -y ${JDK_RH} ;
            yum install -y cassandra ) 2>&1 >/dev/null ;

            HEAP_NEWSIZE=500m MAX_HEAP_SIZE=1g MAX_DIRECT_MEMORY_SIZE=1g cassandra -R -f -Dcassandra.ring_delay_ms=1000" &> procfifo &
        PID=$!
        check_output $PID "Starting listening for CQL clients on"
    done
done

rm -f procfifo
cd -
echo "Done."

`$has_failure` && { echo >&2 "Validation check failed"; exit 1; }