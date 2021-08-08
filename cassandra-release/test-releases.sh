#!/bin/bash

# Purpose: Analyse all known releases and test that the installation instruction work as intended. Intended to be run on a regular basis to ensure that extant releases work.
# Example use: `./test-releases.sh 
# It would be ideal to find a way to auto-discover all known releases and test them. As is, this is stored in an array, below.


RELEASES=(311x 40x 30x 22x)

########################################################
# Check Debian #########################################
########################################################

function test_deb() {
    CASSANDRA_VER=$1
    echo
    echo "testing Cassandra version $CASSANDRA_VER"
    COMMAND="(apt -qq update;
        apt -qq install -y python python3 sudo curl gnupg;
        mkdir -p /usr/share/man/man1
        echo deb https://downloads.apache.org/cassandra/debian $CASSANDRA_VER main | sudo tee -a /etc/apt/sources.list.d/cassandra.sources.list;
        curl https://downloads.apache.org/cassandra/KEYS | sudo apt-key add -;
        # sudo apt-key adv --keyserver pool.sks-keyservers.net --recv-key A278B781FE4B2BDA; 
        sudo apt-get update;
        sudo apt-get install -y cassandra) 2>/dev/null;
        CASSANDRA_CONF=file:///etc/cassandra/ HEAP_NEWSIZE=500m MAX_HEAP_SIZE=1g cassandra -R -f
        "
    rm -f procfifo && mkfifo procfifo
    docker run -i openjdk:8-jdk-slim-buster timeout 180 /bin/bash -c $COMMAND 2>&1 >procfifo &
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
}

for i in $RELEASES; do 
  test_deb $i;
done;
