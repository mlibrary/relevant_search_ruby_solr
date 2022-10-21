require 'rsolr'
require 'json'
require 'pry-byebug'
require 'set'

SOLR_BASE= "http://solr:8983/solr"

def search(query)
  solr = RSolr.connect(url: "#{SOLR_BASE}/tmdb")

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

def summary(results)
  desc = "Num\tRelevance Score\t\tMovie Title\n"
  results["response"]["docs"].each_with_index do |doc,index|
    desc << "#{index}\t#{doc["score"]}\t\t#{doc["title"]}\n"
  end
  
  desc
end

def explain(results)
  desc = ""

  results["response"]["docs"].each_with_index do |doc,index|
    desc << "#{index}\t#{doc["score"]}\t\t#{doc["title"]}\n"
    desc << doc["[explain]"]
    desc << "\n\n"
  end
  
  desc
end

puts <<~EOT
  To get started, try: 

  puts summary(search(q: "basketball with cartoon aliens", defType: "edismax", qf: "title^10 overview"))
EOT

require 'pry'
binding.pry

1
