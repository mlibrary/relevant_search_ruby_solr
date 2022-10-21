This repository allows the reader to use Ruby and Solr to follow along with the
examples in chapter 3 of [Relevant
Search](https://learning.oreilly.com/library/view/relevant-search-with/9781617292774/)

It contains:

* a `docker-compose` setup to run Solr locally, and enough to get a core set up
  with the default "schemaless" configuration

* a Ruby script for configuring Solr field definitions (if needed) and loading documents (`reindex.rb`)

* an example of using RSolr to query the core (`query.rb`)

## Getting Started

* Clone, including the submodule with the example data

```bash
git clone --recurse-submodules 
```

* Run the setup script to set up Solr such that we can create a core and index documents

```bash
./setup.sh
```

## Indexing

Index documents:
```
docker-compose run --rm index
```

Adjusting field definitions / anaylzers to ensure `title` and `overview` use
text\_en which includes stopwords and stemming filters: 

uncomment lines 54-55 in `configure_schema` in `reindex.rb`

See also comments in `reindex.rb`.

### A Note on Nested Documents

Note that the TMDB data set includes nested documents (e.g. cast, location).
Although Solr [can index nested
documents](https://solr.apache.org/guide/solr/latest/indexing-guide/indexing-nested-documents.html)
it requires some more work, and nothing in Chapter 3 requires the data from
those nested documents. So, `reindex.rb` includes logic to throw away nested
documents.

See `reindex_nested_docs.rb` for an example that sets
up the field definitions for nested fields, adds document IDs to index the
nested documents, and adds a field to indicate whether a document is a parent
or child document. To retrieve nested documents, append `[child]` to the field
list (`fl`) parameter when querying. There is also a way to query child
documents alongside the parent documents -- see the [Block Join Children Query
Parser](https://solr.apache.org/guide/solr/latest/query-guide/block-join-query-parser.html)
and [Searching Nested
Documents](https://solr.apache.org/guide/solr/latest/query-guide/searching-nested-documents.html)).

## Querying

```
docker-compose run --rm query
```

Some things you might try doing in pry:

```ruby
params = {q: "basketball with cartoon aliens", defType: "edismax", qf: "title^10 overview"}
puts summary(search(params))

puts summary(search(params))
```

Get query debugging information

```ruby
debug = search(params.merge({debugQuery: true}))["debug"]["parsedquery_toString"]
```

Explaining results

```
puts explain(search(params))
```

## Debugging Analysis

```
http://localhost:8983/solr/#/tmdb/analysis?analysis.fieldvalue=Fire%20with%20Fire&analysis.fieldname=title&verbose_output=1
```

