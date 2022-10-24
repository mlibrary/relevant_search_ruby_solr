#!/bin/bash

echo "🧙 setting permissions for the solr data volume"
docker-compose run --rm --user root solr chown -v solr /var/solr/data

echo "⚙️ making the '_default' confisgset available'"

docker-compose run --rm solr bash -c "mkdir -v /var/solr/data/configsets; cp -vrp /opt/solr/server/solr/configsets/_default /var/solr/data/configsets"

echo "💎 installing gems"
docker-compose run --rm query bundle install

echo "🏃 starting solr (docker-compose logs -f solr to see what's happening)"
docker-compose up -d solr
 
echo "🌞 all set!"
