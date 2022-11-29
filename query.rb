require "rsolr"
require "json"
require "pry-byebug"
require "set"

SOLR_BASE = "http://solr:8983/solr"

def solr
  RSolr.connect(url: "#{SOLR_BASE}/tmdb")
end

def search(query)
  # Solr doesn't return score by default
  #
  # [explain] gives some information about how the relevance was computed
  # alongside the document rather than having to dig it out from debugQuery
  #
  # If you indexed with nested documents, try adding [child] here
  query[:fl] ||= "*,score,[explain]"
  # query[:fl] ||= "*,score,[child],[explain]"

  solr.select params: query
end

def parse(query)
  solr.select(params: query.merge(rows: 0, debugQuery: true))["debug"]["parsedquery_toString"]
end

def summary(results)
  desc = "Num\tRelevance Score\t\tMovie Title\n"
  results["response"]["docs"].each_with_index do |doc, index|
    desc << "#{index}\t#{doc["score"]}\t\t#{doc["title"]}\n"
  end

  desc
end

def explain(results)
  desc = ""

  results["response"]["docs"].each_with_index do |doc, index|
    desc << "#{index}\t#{doc["score"]}\t\t#{doc["title"]}\n"
    desc << doc["[explain]"]
    desc << "\n\n"
  end

  desc
end

puts <<~EOT
  To get started, try: 

  q =  { q: "basketball with cartoon aliens", defType: "edismax", qf: "title^10 overview" }

  puts parse(q)
  puts summary(search(q))
  puts explain(search(q))
EOT

require "pry"
binding.pry

1
