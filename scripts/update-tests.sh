#!/bin/bash -x

TEST_OPTS=$(echo -f common/examples/values-secret.yaml -f values-global.yaml --set global.repoURL="https://github.com/pattern-clone/mypattern" \
    --set main.git.repoURL="https://github.com/pattern-clone/mypattern" --set main.git.revision=main --set global.pattern="mypattern" \
    --set global.namespace="pattern-namespace" --set global.hubClusterDomain=hub.example.com --set global.localClusterDomain=region.example.com \
    --set "clusterGroup.imperative.jobs[0].name"="test" --set "clusterGroup.imperative.jobs[0].playbook"="ansible/test.yml" \
    --set clusterGroup.insecureUnsealVaultInsideCluster=true)

echo $TEST_OPTS

rm tests/*

for i in $(find . -type f -iname 'Chart.yaml' -not -path "./common/*" -exec dirname "{}"  \; | sed -e 's/.\///'); do \
s=$(echo $i | sed -e s@/@-@g -e s@charts-@@); echo $s; helm template $i --name-template $s > tests/$s-naked.expected.yaml; done

for i in $(find . -type f -iname 'Chart.yaml' -not -path "./common/*" -exec dirname "{}"  \; | sed -e 's/.\///'); do \
s=$(echo $i | sed -e s@/@-@g -e s@charts-@@); echo $s; helm template $i --name-template $s $TEST_OPTS > tests/$s-normal.expected.yaml; done
