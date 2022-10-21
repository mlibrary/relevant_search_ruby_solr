#!/usr/bin/env ruby

require 'rsolr'
require 'json'
require 'pry-byebug'
require 'set'

SOLR_BASE= "http://solr:8983/solr"

def main
  reindex(movieDict: throw_away_subdocs(extract))
end

def extract(filename="tmdb.json")
  JSON.parse(File.read(filename))
end

def throw_away_subdocs(data)
  # The examples in chapter 3 don't query any of the subdocument fields, so
  # we're just going to throw away any fields where either:
  #   - the value is a hash
  #   - the value is an array of hashes
  
  data.transform_values do |document|
    document.delete_if do |k,v|
      v.is_a?(Hash) || v.is_a?(Array) and v.any? { |sub_v| sub_v.is_a?(Hash) }
    end
  end
end

def reinitialize_core
  # We aren't running in SolrCloud mode (we only have a single Solr instance),
  # so we don't need to worry about specifying the number of replicas/shards as
  # in the ElasticSearch example. If we want to specify the analysis settings,
  # we'll need to change the solr configuration, which we can do later. Here,
  # we're using the default schema-less configuration that comes with Solr.
  # (https://solr.apache.org/guide/8_4/schemaless-mode.html)
  #
  solr_admin = RSolr.connect(url: "#{SOLR_BASE}/admin")

  begin
    solr_admin.cores params: { action: "UNLOAD", core: "tmdb", deleteInstanceDir: true }
  rescue RSolr::Error::Http => e
    puts "Couldn't unload core (it may not exist): #{e.message}"
  end

  solr_admin.cores params: { action: "CREATE", name: "tmdb", configSet: "_default" }
end

def configure_schema(solr)
  puts "Configuring schema..."
  fields = [
    # Using English analyzers for fields we're searching
    # { name: "title", type: "text_en" },
    # { name: "overview", type: "text_en" },
  ]

  existing_fields = (solr.get "schema/fields")["fields"].map { |f| f["name"] }.to_set
  replace_fields = fields.select { |f| existing_fields.include?(f[:name]) }
  create_fields = fields.reject { |f| existing_fields.include?(f[:name]) }

  if(replace_fields.any?)
    solr.connection.post('schema', { "replace-field" => replace_fields }.to_json, "Content-Type" => "application/json")
  end

  if(create_fields.any?)
    solr.connection.post('schema', { "add-field" => create_fields }.to_json, "Content-Type" => "application/json")
  end
end


def reindex(movieDict: {})
  # Make sure the tmdb core exists and is empty
  reinitialize_core

  # In the ElasticSearch example, we needed to add special parameters for
  # indexing -- "_index", "_type", "_id". For Solr, it picks up the ID from the
  # document itself since it already has an ID field, so all we need to do is
  # turn the dictionary from tmdb.json into an array of JSON documents.
  #
  # The Rsolr gem also takes care of the JSON serialization for us, whereas the
  # elasticsearch example is using the python HTTP library (requests) directly
  # rather than any higher-level API for Solr.
  solr = RSolr.connect(url: "#{SOLR_BASE}/tmdb")

  configure_schema(solr)

  puts "Indexing documents..."
  solr.add movieDict.values

  # Ensure solr commits documents before moving on...
  puts "Committing..."
  solr.commit

  puts "🎉 Done, try: docker-compose run --rm bundle exec ruby query.rb"
end

main if __FILE__ == $0
