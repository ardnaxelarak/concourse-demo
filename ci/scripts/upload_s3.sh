#!/bin/bash

mkdir out

echo "fish" > out/stemcell-version

cd concourse-demo/ci

mkdir out

echo "fish2" > out/stemcell-version

echo "Finished"
