#!/bin/bash
#
# simple crawl script for archiving the key build and test result webapges on ci-cassandra.apache.org
#

for pipeline in "2.2" "3.0" "3.11" "4.0" "trunk" "devbranch" ; do
    for job_suffix in "" "-artifacts" "-cqlsh-tests" "-dtest" "-dtest-large" "-dtest-novnode" "-dtest-offheap" "-dtest-upgrade" "-fqltool-test" "-jvm-dtest" "-jvm-dtest-upgrade" "-long-test" "-stress-test" "-test" "-test-burn" "-test-cdc" "-test-compression" "-microbench" ; do
        latest_url="https://ci-cassandra.apache.org/job/Cassandra-${pipeline}${job_suffix}/lastSuccessfulBuild/api/json?tree=number"
        if curl --output /dev/null --silent --head --fail ${latest_url}; then
            latest=$(curl -s ${latest_url} | jq '.number')
            latest_saved=0
            for latest_saved in $(seq ${latest_saved} ${latest}) ; do
              next_build=$((${latest_saved}+1))
              if curl --output /dev/null --silent --head --fail "https://ci-cassandra.apache.org/job/Cassandra-${pipeline}${job_suffix}/${next_build}/api/json?tree=number" ; then
                if ! curl --output /dev/null --silent --head --fail "https://nightlies.apache.org/cassandra/ci-cassandra.apache.org/job/Cassandra-${pipeline}${job_suffix}/${next_build}" ; then
                  break
                fi
              fi
            done
            echo "Latest build for Cassandra-${pipeline}${job_suffix}/ is ${latest} (last saved was ${latest_saved})"
            if (( ${latest} > ${latest_saved} )) ; then
                for build_number in $(seq $((${latest_saved}+1)) ${latest}) ; do
                    main_url="https://ci-cassandra.apache.org/job/Cassandra-${pipeline}${job_suffix}/${build_number}/"
                    wget -q -E -N -k -p "${main_url}"
                    wget -q -E -N -k -p "${main_url}/testReport/"
                    if test -f ci-cassandra.apache.org/job/Cassandra-${pipeline}${job_suffix}/${build_number}/testReport/index.html ; then
                        mkdir -p ci-cassandra.apache.org/blue/organizations/jenkins/Cassandra-${pipeline}${job_suffix}/detail/Cassandra-${pipeline}${job_suffix}/${build_number}/pipeline
                        cp ci-cassandra.apache.org/job/Cassandra-${pipeline}${job_suffix}/${build_number}/testReport/index.html ci-cassandra.apache.org/blue/organizations/jenkins/Cassandra-${pipeline}${job_suffix}/detail/Cassandra-${pipeline}${job_suffix}/${build_number}/pipeline/
                    fi
                    echo "Saved Cassandra-${pipeline}${job_suffix}/${build_number}"
                done
            fi
        fi
    done
done
