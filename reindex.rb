#!/usr/bin/env ruby

require "rsolr"
require "json"
require "pry-byebug"
require "set"

SOLR_BASE = "http://solr:8983/solr"

OMIT_NORMS = true

def main
  SolrIndexer.new.reindex
end

class SolrIndexer
  attr_reader :filename, :solr_base, :core, :solr

  def initialize(filename: "tmdb.json", core: "tmdb", solr_base: SOLR_BASE)
    @filename = filename
    @solr_base = SOLR_BASE
    @core = core
    @solr = RSolr.connect(url: "#{@solr_base}/#{@core}")
  end

  def extract
    JSON.parse(File.read(filename))
  end

  def throw_away_subdocs(data)
    # The examples in chapter 5 only query the "name" field from the subdocuments, so we're going to:
    #   - make a new field based on "name", if it's present
    #   - throw away the original subdocuments

    data.transform_values do |document|
      to_add = {}
      document.each do |k,v|
        %w(name character).each do |subfield|
          if v.is_a?(Hash) and v.has_key?(subfield)
            to_add[k + ".#{subfield}"] = v[subfield]
            to_add[k + ".#{subfield}.bigrammed"] = v[subfield]
          elsif v.is_a?(Array) and v.any? { |sub_v| sub_v.is_a?(Hash) }
            to_add[k + ".#{subfield}"] = v.select { |subv| subv.has_key?(subfield) }.map { |subv| subv[subfield] }
            to_add[k + ".#{subfield}.bigrammed"] = v.select { |subv| subv.has_key?(subfield) }.map { |subv| subv[subfield] }
          end
        end
        to_add["title.exact"] = "SENTINEL_BEGIN #{document["title"]} SENTINEL_END"

        %w(cast.name directors.name).each do |f|
          next unless to_add.has_key?(f)
          to_add["#{f}.exact"] = to_add[f].map { |v| "SENTINEL_BEGIN #{v} SENTINEL_END" }
        end
      end
      document.merge!(to_add)

      document.delete_if do |k, v|
        v.is_a?(Hash) or (v.is_a?(Array) and v.any? { |sub_v| sub_v.is_a?(Hash) })
      end
    end
  end

  def reinitialize_core
    # We aren't running in SolrCloud mode (we only have a single Solr
    # instance), so we don't need to worry about specifying the number of
    # replicas/shards as in the ElasticSearch example.
    #
    # This starts using the default schema-less configuration that comes with
    # Solr (https://solr.apache.org/guide/8_4/schemaless-mode.html)
    #
    # If we want to change the analysis pipeline, we'll need to change the
    # schema, which we can do in configure_field_types/configure_fields below.
    puts "📚 Creating or reinitializing core..."
    solr_admin = RSolr.connect(url: "#{solr_base}/admin")

    status = solr_admin.cores params: {action: "STATUS", core: core}
    core_exists = status["status"][core].has_key?("uptime")

    if core_exists
      begin
        solr_admin.cores params: {action: "UNLOAD", core: core, deleteInstanceDir: true}
      rescue RSolr::Error::Http => e
        puts "Couldn't unload core: #{e.message}"
      end
    end

    solr_admin.cores params: {action: "CREATE", name: core, configSet: "_default"}
  end

  def upsert_schema(values, get_endpoint:, get_key:, replace:, add:)
    existing_values = (solr.get get_endpoint)[get_key].map { |f| f["name"] }.to_set
    replace_values = values.select { |f| existing_values.include?(f[:name]) }
    create_values = values.reject { |f| existing_values.include?(f[:name]) }

    if replace_values.any?
      solr.connection.post("schema", {replace => replace_values}.to_json, "Content-Type" => "application/json")
    end

    if create_values.any?
      solr.connection.post("schema", {add => create_values}.to_json, "Content-Type" => "application/json")
    end

  end

  def configure_suggester
    begin
      solr.connection.post("config", { "delete-requesthandler" => "/suggest" }.to_json, "Content-Type" => "application/json")
    rescue Faraday::BadRequestError
    end
    begin
      solr.connection.post("config", { "delete-searchcomponent" => "suggest" }.to_json, "Content-Type" => "application/json")
    rescue Faraday::BadRequestError
    end
    
    suggester = {
      name: "suggest",
      class: "solr.SuggestComponent",
      suggester: {
        name: "mySuggester",
        lookupImpl: "FuzzyLookupFactory",
        dictionaryImpl: "DocumentDictionaryFactory",
        field: "title",
        weightField: "popularity",
        suggestAnalyzerFieldType: "string"
      },

    }

    solr.connection.post("config",
                         { "add-searchcomponent" => suggester }.to_json,
                         "Content-Type" => "application/json")

    requestHandler = {
      name: "/suggest",
      class: "solr.SearchHandler",
      defaults: {
        suggest: true,
        "suggest.count" => 10
      }, 
      components: [ 'suggest' ]
    }

    solr.connection.post("config",
                         { "add-requesthandler" => requestHandler }.to_json,
                         "Content-Type" => "application/json")
  end

  def upsert_fields(fields)
    upsert_schema(fields,
      get_endpoint: "schema/fields",
      get_key: "fields",
      add: "add-field",
      replace: "replace-field")
  end

  def upsert_field_types(field_types)
    upsert_schema(field_types,
      get_endpoint: "schema/fieldtypes",
      get_key: "fieldTypes",
      add: "add-field-type",
      replace: "replace-field-type")
  end

  def configure_field_types
    puts "🗒️Configuring field types..."

    field_types = [
      {
        name: "text_en_clone",
        class: "solr.TextField",
        analyzer: {
          name: "tokenizerChain",
          tokenizer: {name: "standard"},
          filters: [
            {name: "stop", words: "lang/stopwords_en.txt"},
            {name: "lowercase"},
            {name: "englishPossessive"},
            {name: "keywordMarker", protected: "protwords.txt"},
            {name: "porterStem"}
          ]
        }
      },

      {
        name: "text_en_bigram",
        class: "solr.TextField",
        analyzer: {
          name: "tokenizerChain",
          tokenizer: {name: "standard"},
          filters: [
            {name: "stop", words: "lang/stopwords_en.txt"},
            {name: "lowercase"},
            {name: "englishPossessive"},
            {name: "keywordMarker", protected: "protwords.txt"},
            {name: "porterStem"},
            {name: "shingle", maxShingleSize: 2, minShingleSize: 2, outputUnigrams: false}
          ]
        }
      },

      {
        name: "text_dbl_metaphone",
        class: "solr.TextField",
        analyzer: {
          name: "tokenizerChain",
          tokenizer: {name: "standard"},
          filters: [
            {name: "lowercase"},
            {name: "phonetic", encoder: "DoubleMetaphone", inject: true}
          ]
        }
      },

    ]

    upsert_field_types(field_types)
  end

  def configure_fields
    puts "🗒️Configuring fields..."
    fields = [
      # Using default English analyzers for fields we're searching
      {name: "title", type: "text_en"},
      {name: "title.exact", type: "text_en"},
      {name: "title_str", type: "string"},
      {name: "overview", type: "text_en"},
      {name: "cast.name", type: "text_en", multiValued: true, omitNorms: OMIT_NORMS},
      {name: "directors.name", type: "text_en", multiValued: true, omitNorms: OMIT_NORMS},
      {name: "people.name", type: "text_en", multiValued: true, omitNorms: OMIT_NORMS},
      {name: "text_all", type: "text_en", multiValued: true},
      {name: "cast.name.bigrammed", type: "text_en_bigram", multiValued: true, omitNorms: OMIT_NORMS},
      {name: "directors.name.bigrammed", type: "text_en_bigram", multiValued: true, omitNorms: OMIT_NORMS},
      {name: "people.name.bigrammed", type: "text_en_bigram", multiValued: true, omitNorms: OMIT_NORMS},
      {name: "cast.name.exact", type: "text_en", multiValued: true, omitNorms: OMIT_NORMS},
      {name: "directors.name.exact", type: "text_en", multiValued: true, omitNorms: OMIT_NORMS},
      {name: "people.name.exact", type: "text_en", multiValued: true, omitNorms: OMIT_NORMS},
      {name: "release_date", type: "pdate", multiValued: false, omitNorms: true},
       {name: "vote_average", type: "pdouble", multiValued: false, omitNorms: true},
       {name: "popularity", type: "pdouble", multiValued: false, omitNorms: true}
      # Using the new field type we defined above
#      {name: "title", type: "text_dbl_metaphone"}
#      {name: "overview", type: "text_dbl_metaphone"}
    ]

    upsert_fields(fields)
  end

  def configure_copy_fields
    puts "🗒️Configuring copy fields..."
    copyFields = [
      {
        "source" => "cast.name.bigrammed",
        "dest" => "people.name.bigrammed",
      },
      {
        "source" => "directors.name.bigrammed",
        "dest" => "people.name.bigrammed"
      },
      {
        "source" => "cast.name",
        "dest" => "people.name",
      },
      {
        "source" => "cast.name",
        "dest" => "people.name_str",
      },
      {
        "source" => "directors.name",
        "dest" => "people.name"
      },
      {
        "source" => "directors.name",
        "dest" => "people.name_str"
      },
      {
        "source" => "cast.name.exact",
        "dest" => "people.name.exact",
      },
      {
        "source" => "directors.name.exact",
        "dest" => "people.name.exact"
      },
      {
        "source" => "cast.name",
        "dest" => "text_all",
      },
      {
        "source" => "directors.name",
        "dest" => "text_all"
      },
      {
        "source" => "title",
        "dest" => "text_all"
      },
      {
        "source" => "title",
        "dest" => "title_str"
      },
      {
        "source" => "overview",
        "dest" => "text_all"
      },
    ]

    existing_values = (solr.get "schema/copyfields")["copyFields"].map { |f| f.slice("source", "dest") }.to_set
    add_values = copyFields.reject { |f| existing_values.include?(f) }

    if add_values.any?
      solr.connection.post("schema", {"add-copy-field" => add_values}.to_json, "Content-Type" => "application/json")
    end
  end

  def reindex(data: throw_away_subdocs(extract))
    # Make sure the tmdb core exists and is empty
    reinitialize_core

    # Configure schema
    configure_suggester
    configure_field_types
    configure_fields
    configure_copy_fields

    puts "📝 Indexing documents..."

    # In the ElasticSearch example, we needed to add special parameters for
    # indexing -- "_index", "_type", "_id". For Solr, it picks up the ID from the
    # document itself since it already has an ID field, so all we need to do is
    # turn the dictionary from tmdb.json into an array of JSON documents.
    #
    # The Rsolr gem also takes care of the JSON serialization for us, whereas the
    # elasticsearch example is using the python HTTP library (requests) directly
    # rather than any higher-level API for Solr.
    solr.add data.values

    # Ensure solr commits documents before moving on...
    puts "💾 Committing..."
    solr.commit

    puts "🎉 Done, try: docker-compose run --rm query"
  end
end

main if __FILE__ == $0
