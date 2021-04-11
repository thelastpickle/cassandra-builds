#!/bin/bash
#
# A wrapper script to cassandra-test.sh
#  that split the test list into multiple docker runs, collecting results.
#
# The docker image used is normally based from those found in docker/testing/
#
# Usage: cassandra-test-docker.sh REPO BRANCH BUILDS_REPO_URL BUILDS_BRANCH DOCKER_IMAGE [target] [split_chunk]
#

if [ "$#" -lt 3 ]; then
    # inside the docker container, setup env before calling cassandra-test.sh
    export WORKSPACE=/home/cassandra/cassandra
    export LANG=en_US.UTF-8
    export LC_CTYPE=en_US.UTF-8
    export PYTHONIOENCODING=utf-8
    export PYTHONUNBUFFERED=true
    if [ "${JAVA_VERSION}" -ge 11 ]; then
        sudo update-java-alternatives --set java-1.11.0-openjdk-$(dpkg --print-architecture)
        export CASSANDRA_USE_JDK11=true
        export JAVA_HOME=$(sudo update-java-alternatives -l | grep "java-1.11.0-openjdk" | awk '{print $3}')
    fi
    java -version
    javac -version
    echo "running: git clone --quiet --depth 1 --single-branch --branch=$BRANCH https://github.com/$REPO/cassandra.git"
    until git clone --quiet --depth 1 --single-branch --branch=$BRANCH https://github.com/$REPO/cassandra.git ; do echo "git clone failed… trying again… " ; done
    cd cassandra
    echo "cassandra-test.sh (${1} ${2}) cassandra: `git log -1 --pretty=format:'%h %an %ad %s'`" | tee "${1}-$(echo $2 | sed 's/\//-/')-cassandra.head"
    echo "cassandra-test.sh (${1} ${2}) cassandra-builds: `git -C ../cassandra-builds log -1 --pretty=format:'%h %an %ad %s'`" | tee -a "${1}-$(echo $2 | sed 's/\//-/')-cassandra.head"
    bash ../cassandra-builds/build-scripts/cassandra-test.sh "$@"
    if [ -d build/test/logs ]; then find build/test/logs -type f -name "*.log" | xargs xz -qq ; fi
else
    # start the docker container
    if [ "$#" -lt 5 ]; then
       echo "Usage: cassandra-test-docker.sh REPO BRANCH BUILDS_REPO_URL BUILDS_BRANCH DOCKER_IMAGE [target] [split_chunk]"
       exit 1
    fi
    BUILDSREPO=$3
    BUILDSBRANCH=$4
    DOCKER_IMAGE=$5
    TARGET=${6:-"test"}
    SPLIT_CHUNK=${7:-"1/1"}

    # Setup JDK
    java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | awk -F. '{print $1}')
    if [ "$java_version" -ge 11 ]; then
        java_version="11"
        if ! grep -q CASSANDRA_USE_JDK11 build.xml ; then
            echo "Skipping build. JDK11 not supported against $(grep 'property\s*name=\"base.version\"' build.xml |sed -ne 's/.*value=\"\([^"]*\)\".*/\1/p')"
            exit 0
        fi
    else
        java_version="8"
    fi

    cat > env.list <<EOF
REPO=$1
BRANCH=$2
JAVA_VERSION=${java_version}
EOF

    # A Jenkins agent is expected to have 8 cores and 16gb ram, for tests we can split that into three
    INNER_SPLITS=$(( $(echo $SPLIT_CHUNK | cut -d"/" -f2 ) * 3 ))
    INNER_SPLIT_THIRD=$(( $(echo $SPLIT_CHUNK | cut -d"/" -f1 ) * 3 ))
    INNER_SPLIT_SECOND=$(( $INNER_SPLIT_THIRD - 1 ))
    INNER_SPLIT_FIRST=$(( $INNER_SPLIT_THIRD - 2 ))

    # docker login to avoid rate-limiting apache images. credentials are expected to already be in place
    docker login || true

    echo "cassandra-test-docker.sh: running: git clone --quiet --single-branch --depth 1 --branch $BUILDSBRANCH $BUILDSREPO; sh ./cassandra-builds/build-scripts/cassandra-test-docker.sh $TARGET ${INNER_SPLIT_FIRST}/${INNER_SPLITS}"
    ID_1=$(docker run -m 5g --memory-swap 5g --env-file env.list -dt $DOCKER_IMAGE dumb-init bash -ilc "until git clone --quiet --single-branch --depth 1 --branch $BUILDSBRANCH $BUILDSREPO ; do echo 'git clone failed… trying again… ' ; done ; sh ./cassandra-builds/build-scripts/cassandra-test-docker.sh ${TARGET} ${INNER_SPLIT_FIRST}/${INNER_SPLITS}")
    echo "cassandra-test-docker.sh: running: git clone --quiet --single-branch --depth 1 --branch $BUILDSBRANCH $BUILDSREPO; sh ./cassandra-builds/build-scripts/cassandra-test-docker.sh $TARGET ${INNER_SPLIT_SECOND}/${INNER_SPLITS}"
    ID_2=$(docker run -m 5g --memory-swap 5g --env-file env.list -dt $DOCKER_IMAGE dumb-init bash -ilc "until git clone --quiet --single-branch --depth 1 --branch $BUILDSBRANCH $BUILDSREPO ; do echo 'git clone failed… trying again… ' ; done ; sh ./cassandra-builds/build-scripts/cassandra-test-docker.sh ${TARGET} ${INNER_SPLIT_SECOND}/${INNER_SPLITS}")
    echo "cassandra-test-docker.sh: running: git clone --quiet --single-branch --depth 1 --branch $BUILDSBRANCH $BUILDSREPO; sh ./cassandra-builds/build-scripts/cassandra-test-docker.sh $TARGET ${INNER_SPLIT_THIRD}/${INNER_SPLITS}"
    ID_3=$(docker run -m 5g --memory-swap 5g --env-file env.list -dt $DOCKER_IMAGE dumb-init bash -ilc "until git clone --quiet --single-branch --depth 1 --branch $BUILDSBRANCH $BUILDSREPO ; do echo 'git clone failed… trying again… ' ; done ; sh ./cassandra-builds/build-scripts/cassandra-test-docker.sh ${TARGET} ${INNER_SPLIT_THIRD}/${INNER_SPLITS}")

    # use docker attach instead of docker wait to get output
    mkdir -p build/test/logs
    docker attach --no-stdin $ID_1 > build/test/logs/docker_attach_1.log &
    process_id_1=$!
    docker attach --no-stdin $ID_2  > build/test/logs/docker_attach_2.log &
    process_id_2=$!
    docker attach --no-stdin $ID_3  > build/test/logs/docker_attach_3.log &
    process_id_3=$!
    wait $process_id_1
    status_1="$?"
    wait $process_id_2
    status_2="$?"
    wait $process_id_3
    status_3="$?"

    if [ "$status_1" -ne 0 ] ; then
        echo "$ID_1 failed (${status}), debug…"
        docker inspect $ID_1
        echo "–––"
        docker logs $ID_1
        echo "–––"
        docker ps -a
        echo "–––"
        docker info
        echo "–––"
        dmesg
    elif [ "$status_2" -ne 0 ] ; then
        echo "$ID_2 failed (${status}), debug…"
        docker inspect $ID_2
        echo "–––"
        docker logs $ID_2
        echo "–––"
        docker ps -a
        echo "–––"
        docker info
        echo "–––"
        dmesg
    elif [ "$status_3" -ne 0 ] ; then
        echo "$ID_3 failed (${status}), debug…"
        docker inspect $ID_3
        echo "–––"
        docker logs $ID_3
        echo "–––"
        docker ps -a
        echo "–––"
        docker info
        echo "–––"
        dmesg
    else
        echo "$ID_1 done (${status_1}), copying files"
        docker cp "$ID_1:/home/cassandra/cassandra/$TARGET-${INNER_SPLIT_FIRST}-${INNER_SPLITS}-cassandra.head" .
        docker cp $ID_1:/home/cassandra/cassandra/build/test/output/. build/test/output
        docker cp $ID_1:/home/cassandra/cassandra/build/test/logs/. build/test/logs
        echo "$ID_2 done (${status_2}), copying files"
        docker cp "$ID_2:/home/cassandra/cassandra/$TARGET-${INNER_SPLIT_SECOND}-${INNER_SPLITS}-cassandra.head" .
        docker cp $ID_2:/home/cassandra/cassandra/build/test/output/. build/test/output
        docker cp $ID_2:/home/cassandra/cassandra/build/test/logs/. build/test/logs
        echo "$ID_3 done (${status_2}), copying files"
        docker cp "$ID_3:/home/cassandra/cassandra/$TARGET-${INNER_SPLIT_THIRD}-${INNER_SPLITS}-cassandra.head" .
        docker cp $ID_3:/home/cassandra/cassandra/build/test/output/. build/test/output
        docker cp $ID_3:/home/cassandra/cassandra/build/test/logs/. build/test/logs
        xz build/test/logs/docker_attach_*.log
    fi

    docker rm ${ID_1}
    docker rm ${ID_2}
    docker rm ${ID_3}
fi
