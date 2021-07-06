#!/bin/bash
set -e

sudo apt install nodejs npm -y
git clone https://github.com/dcarr178/har2openapi
cd har2openapi
npm install
cp ../config.json.har2openapi config.json

# cd agora
cd ../..
# disable HTTPS on all nodes by removing the related files
rm -rf tests/system/node/*/*.pem

# replace https urls with http
for node in tests/system/node/*;
do
    sed -i 's/https/http/g' $node/config.yaml;
done

# enable proxy on node-2
cp tests/system/node/2/config.yaml tests/system/node/2/config.yaml.bkp
echo -e "\nproxy:\n  url: http://har-recorder:8080" >>  tests/system/node/2/config.yaml

# nobuild, integration test already built the image
./ci/fuzz.d nobuild record

cd scripts/har2openapi
# generate spec
node index.js examples ../../tests/system/output.har

stat output/examples.spec.json
