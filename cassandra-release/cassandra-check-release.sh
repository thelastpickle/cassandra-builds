#!/bin/bash

# Parameters
# $1 release
# $2 maven artefacts url (as specified in the vote email)
#
# Example use: `./cassandra-check-release.sh 4.0-beta3 https://repository.apache.org/content/repositories/orgapachecassandra-1224/org/apache/cassandra/cassandra-all/4.0-beta3/`
#
# This script is very basic and experimental. I beg of you to help improve it.
#

###################
# prerequisites

command -v wget >/dev/null 2>&1 || { echo >&2 "wget needs to be installed"; exit 1; }
command -v gpg >/dev/null 2>&1 || { echo >&2 "gpg needs to be installed"; exit 1; }
command -v sha1sum >/dev/null 2>&1 || { echo >&2 "sha1sum needs to be installed"; exit 1; }
command -v md5sum >/dev/null 2>&1 || { echo >&2 "md5sum needs to be installed"; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo >&2 "sha256sum needs to be installed"; exit 1; }
command -v sha512sum >/dev/null 2>&1 || { echo >&2 "sha512sum needs to be installed"; exit 1; }
command -v tar >/dev/null 2>&1 || { echo >&2 "tar needs to be installed"; exit 1; }
command -v ant >/dev/null 2>&1 || { echo >&2 "ant needs to be installed"; exit 1; }
command -v timeout >/dev/null 2>&1 || { echo >&2 "timeout needs to be installed"; exit 1; }
command -v docker >/dev/null 2>&1 || { echo >&2 "docker needs to be installed"; exit 1; }
(docker info >/dev/null 2>&1) || { echo >&2 "docker needs to running"; exit 1; }
(java -version 2>&1 | grep -q "1.8") || { echo >&2 "Java 8 must be used"; exit 1; }
(java -version 2>&1 | grep -iq jdk ) || { echo >&2 "Java JDK must be used"; exit 1; }

###################

mkdir -p /tmp/$1
cd /tmp/$1
echo "Downloading KEYS"
wget https://downloads.apache.org/cassandra/KEYS
echo "Downloading $2"
wget -Nqnd -e robots=off --recursive --no-parent $2
echo "Downloading https://dist.apache.org/repos/dist/dev/cassandra/$1/"
wget -Nqe robots=off --recursive --no-parent https://dist.apache.org/repos/dist/dev/cassandra/$1/

echo
echo "====== CHECK RESULTS ======"
echo

gpg --import KEYS

for f in *.asc ; do gpg --verify $f ; done
for f in *.pom *.jar *.asc ; do echo -n "sha1: " ; echo "$(cat $f.sha1) $f" | sha1sum -c ; echo -n "md5: " ; echo "$(cat $f.md5) $f" | md5sum -c ; done

cd dist.apache.org/repos/dist/dev/cassandra/$1
for f in *.asc ; do gpg --verify $f ; done
for f in *.gz ; do echo -n "sha256: " ; echo "$(cat $f.sha256) $f" | sha256sum -c ; echo -n "sha512:" ; echo "$(cat $f.sha512) $f" | sha512sum -c ; done

echo
rm -fR apache-cassandra-$1-src
tar -xjf apache-cassandra-$1-src.tar.gz
pushd apache-cassandra-$1-src
echo "Source build $(ant artifacts | grep '^BUILD ')"
popd

echo
rm -fR apache-cassandra-$1
tar -xjf apache-cassandra-$1-bin.tar.gz
rm -f procfifo
mkfifo procfifo
timeout 30 apache-cassandra-$1/bin/cassandra -f 2>&1  >procfifo &
PID=$!
success=false
while read LINE && ! $success ; do
    if [[ $LINE =~ "Starting listening for CQL clients on" ]] ; then
        echo "Binary artefact OK"
        kill "$PID"
        success=true
    fi
done < procfifo
rm -f procfifo
wait "$PID"
if ! $success ; then
    echo "Binary artefact FAILED"
fi

echo
rm -f procfifo
mkfifo procfifo
docker run -i -v `pwd`/debian:/debian openjdk:8-jdk-slim-buster timeout 180 /bin/bash -c "( apt -qq update; apt -qq install -y python python3; dpkg --ignore-depends=java7-runtime --ignore-depends=java8-runtime -i debian/*.deb ) 2>/dev/null; CASSANDRA_CONF=file:///etc/cassandra/ HEAP_NEWSIZE=500m MAX_HEAP_SIZE=1g cassandra -R -f" 2>&1 >procfifo &
PID=$!
success=false
while read LINE && ! $success ; do
    if [[ $LINE =~ "Starting listening for CQL clients on" ]] ; then
        echo "Debian package OK"
        kill "$PID"
        success=true
    fi
done < procfifo
rm -f procfifo
wait "$PID"
if ! $success ; then
    echo "Debian package FAILED"
fi

echo
rm -f procfifo
mkfifo procfifo
docker run -i -v `pwd`/redhat:/redhat centos timeout 180 /bin/bash -c "( yum install -y java-1.8.0-openjdk ; rpm -i redhat/*.rpm ) 2>/dev/null; cassandra -R -f " 2>&1  >procfifo &
PID=$!

success=false
while read LINE && ! $success ; do
    if [[ $LINE =~ "Starting listening for CQL clients on" ]] ; then
        echo "Redhat package OK"
        kill "$PID"
        success=true
    fi
done < procfifo
rm -f procfifo
wait "$PID"
if ! $success ; then
    echo "Redhat package FAILED"
fi

# Commented this out as it was just for my testing (when we don't have artefacts in staging). Directory structures I get are different to those the script seems to expect (e.g. I have .../redhat/311x/, script seems to expect .../311x/redhat).
# wget -Nqe robots=off --recursive --no-parent https://downloads.apache.org/cassandra/redhat/311x/
# wget https://downloads.apache.org/cassandra/KEYS
# cd downloads.apache.org/cassandra/
# mv redhat/311x/* redhat/ 
mv KEYS redhat 

echo
rm -f procfifo
mkfifo procfifo
docker run -i -v `pwd`/redhat:/redhat centos timeout 180 /bin/bash -c "( rpm --import /redhat/KEYS; rpm -K /redhat/*.rpm);" 2>&1  >procfifo &
PID=$!
failed=false
while read LINE; do 
    if [[ $LINE =~ ".*digests SIGNATURES NOT OK" ]] ; then
        echo "RPM verification error."
        kill "$PID"; 
        failed=true; 
        break;
    fi
done < procfifo
rm -f procfifo
wait "$PID"
if [[ $failed == false ]]; then
    echo "RPMs verified correctly."
fi