#!/usr/bin/env ruby

require 'rsolr'
require 'json'
require 'pry-byebug'
require 'set'

SOLR_BASE= "http://solr:8983/solr"

def main
  reindex(movieDict: add_subdoc_keys(extract))
end

def extract(filename="tmdb.json")
  JSON.parse(File.read(filename))
end

def add_subdoc_keys(data)
  # Indexing nested documents is possible in Solr, but we need to make sure
  # that 1) every document has an ID and 2) we have a way to tell which
  # doucments are parents and which are children.
  
  max_id = data.keys.map(&:to_i).max

  # iterate through documents and fields; add "id" and "node_type" field to embedded documents
  data.transform_values do |document|
    document["node_type"] = "parent"
    document.transform_values do |field|
      # is field an array of objects?
      if field.is_a? Array then
        field.each do |subdoc|
          subdoc["id"] = (max_id += 1) if subdoc.is_a? Hash
          subdoc["node_type"] = "child"
        end
      else
        field
      end
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
    # Get the existing field names & make sure we don't add any that already exist
    # Fields that show up in nested documents, 
    { name: "iso_3166_1", type: "string" },
    { name: "iso_639_1", type: "string" },
    { name: "name", type: "text_en" },
    { name: "character", type: "text_en" },
    { name: "credit_id", type: "string" },
    { name: "cast_id", type: "pint" },
    { name: "department", type: "text_en" },
    { name: "job", type: "text_en" },
    { name: "profile_path", type: "string" },
    { name: "order", type: "pint" },
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


def reindex(analysisSettings: {}, mappingSettings: {}, movieDict: {})
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
