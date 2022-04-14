#!/bin/bash
#
#curl --output /dev/null --silent --head --fail https://ci-cassandra.apache.org || { echo "cannot reach ci-cassandra.apache.org" ; exit 1 }

rm -fr jq ci-cassandra.apache.org

if command -v jq ; then
  cp $(command -v jq) jq
else
  wget -q https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
  mv jq-linux64 jq
  chmod +x jq
fi

#for pipeline in "2.2" "3.0" "3.11" "4.0" "trunk" "devbranch" ; do
#    for job_suffix in "" "-artifacts" "-cqlsh-tests" "-dtest" "-dtest-large" "-dtest-novnode" "-dtest-offheap" "-dtest-upgrade" "-fqltool-test" "-jvm-dtest" "-jvm-dtest-upgrade" "-long-test" "-stress-test" "-test" "-test-burn" "-test-cdc" "-test-compression" "-microbench" ; do
      for pipeline in "3.0"  ; do
          for job_suffix in "" "-artifacts" ; do      
        echo "Searching Cassandra-${pipeline}${job_suffix}"
        latest_url="https://ci-cassandra.apache.org/job/Cassandra-${pipeline}${job_suffix}/lastSuccessfulBuild/api/json?tree=number"
        if curl --output /dev/null --silent --head --fail ${latest_url}; then
            latest=$(curl -s ${latest_url} | ./jq '.number')
            latest_saved=0
            for latest_saved in $(seq ${latest_saved} ${latest}) ; do
              next_build=$((${latest_saved}+1))
              if curl --output /dev/null --silent --head --fail "https://ci-cassandra.apache.org/job/Cassandra-${pipeline}${job_suffix}/${next_build}/api/json?tree=number" ; then
                if ! curl --output /dev/null --silent --head --fail "https://nightlies.apache.org/cassandra/ci-cassandra.apache.org/job/Cassandra-${pipeline}${job_suffix}/${next_build}/index.html" ; then
                  break
                fi
              fi
            done
            latest_testreport_saved=0
            if [ "${job_suffix}"  != "-artifacts" ] ; then
              for latest_testreport_saved in $(seq ${latest_testreport_saved} ${latest}) ; do
                next_build=$((${latest_testreport_saved}+1))
                if curl --output /dev/null --silent --head --fail "https://ci-cassandra.apache.org/job/Cassandra-${pipeline}${job_suffix}/${next_build}/api/json?tree=number" ; then
                  if ! curl --output /dev/null --silent --head --fail "https://nightlies.apache.org/cassandra/ci-cassandra.apache.org/job/Cassandra-${pipeline}${job_suffix}/${next_build}/testReport/index.html" ; then
                    break
                  fi
                fi
              done
            fi
            echo "Latest build for Cassandra-${pipeline}${job_suffix}/ is ${latest} (last saved was ${latest_saved}, last saved testReport ${latest_testreport_saved})"
            if (( ${latest} > ${latest_saved} )) ; then
                for build_number in $(seq $((${latest_saved}+1)) ${latest}) ; do
                    main_url="https://ci-cassandra.apache.org/job/Cassandra-${pipeline}${job_suffix}/${build_number}/"
                    if curl --output /dev/null --silent --head --fail "https://nightlies.apache.org/cassandra/ci-cassandra.apache.org/job/Cassandra-${pipeline}${job_suffix}/${next_build}/" ; then
                      wget -q -E -N -k -p $main_url
                      mkdir ci-cassandra.apache.org/job/Cassandra-${pipeline}${job_suffix}/${build_number}/testReport
                    else
                      mkdir ci-cassandra.apache.org/job/Cassandra-${pipeline}${job_suffix}/${build_number}
                    fi
                    echo "Saved Cassandra-${pipeline}${job_suffix}/${build_number}"
                    exit 0
                done
            fi
            if (( ${latest} > ${latest_testreport_saved} )) ; then
                for build_number in $(seq $((${latest_testreport_saved}+1)) ${latest}) ; do 
                    main_url="https://ci-cassandra.apache.org/job/Cassandra-${pipeline}${job_suffix}/${build_number}/"
                    if curl --output /dev/null --silent --head --fail "https://nightlies.apache.org/cassandra/ci-cassandra.apache.org/job/Cassandra-${pipeline}${job_suffix}/${next_build}/testReport" ; then
                      wget -q -E -N -k -p ${main_url}/testReport/
                      if test -f ci-cassandra.apache.org/job/Cassandra-${pipeline}${job_suffix}/${build_number}/testReport ; then
                          mkdir -p ci-cassandra.apache.org/blue/organizations/jenkins/Cassandra-${pipeline}${job_suffix}/detail/Cassandra-${pipeline}${job_suffix}/${build_number}/pipeline
                          cp ci-cassandra.apache.org/job/Cassandra-${pipeline}${job_suffix}/${build_number}/testReport/index.html ci-cassandra.apache.org/blue/organizations/jenkins/Cassandra-${pipeline}${job_suffix}/detail/Cassandra-${pipeline}${job_suffix}/${build_number}/pipeline/
                      fi
                    else
                      mkdir ci-cassandra.apache.org/job/Cassandra-${pipeline}${job_suffix}/${build_number}/testReport
                    fi
                    echo "Saved testReport Cassandra-${pipeline}${job_suffix}/${build_number}"
                    exit 0
                done
            fi
        fi
    done
done
