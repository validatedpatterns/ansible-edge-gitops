#!/bin/bash

rm tests/*

for i in $(find . -type f -iname 'Chart.yaml' -not -path "./common/*" -exec dirname "{}"  \; | sed -e 's/.\///'); do \
s=$(echo $i | sed -e s@/@-@g -e s@charts-@@); echo $s; helm template $i --name-template $s > tests/$s-naked.expected.yaml; done

for i in $(find . -type f -iname 'Chart.yaml' -not -path "./common/*" -exec dirname "{}"  \; | sed -e 's/.\///'); do \
s=$(echo $i | sed -e s@/@-@g -e s@charts-@@); echo $s; helm template $i --name-template $s $@ > tests/$s-normal.expected.yaml; done
