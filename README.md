This repository allows the reader to use Ruby and Solr to follow along with the
examples in chapters 3 and 4 of [Relevant
Search](https://learning.oreilly.com/library/view/relevant-search-with/9781617292774/)

It contains:

* a `docker-compose` setup to run Solr locally, and enough to get a core set up
  with the default "schemaless" configuration

* a Ruby script for configuring Solr field definitions (if needed) and loading documents (`reindex.rb`)

* an example of using RSolr to query the core (`query.rb`)

## Getting Started

* Clone, including the submodule with the example data

```bash
git clone --recurse-submodules https://github.com/mlibrary/relevant_search_ruby_solr/
```

* Run the setup script to set up Solr such that we can create a core and index documents

```bash
./setup.sh
```

## Indexing

Index documents with `reindex.rb`:

```
docker-compose run --rm index
```

### Field Types and Field Definitions

To adjust field and field type definitions -- see the methods
`configure_fields` and `configure_field_types` and add the field type
definition there.

`reindex.rb` already includes Solr versions of some of the example analysis chains from Chapter 4; try
running `docker compose --rm index` to set up the field types, then [try
analyzing text using the phonetic
analysis](http://localhost:8983/solr/#/tmdb/analysis?analysis.fieldtype=text_dbl_metaphone)

Try setting up your own for the other examples using the information on filters
from [the solr documentation on
filters](https://solr.apache.org/guide/solr/latest/indexing-guide/filters.html);
in particular, experiment with:

* [Word Delimiter Grpah
Filter](https://solr.apache.org/guide/solr/latest/indexing-guide/filters.html#word-delimiter-graph-filter)
* [Pattern Replace Filter](https://solr.apache.org/guide/solr/latest/indexing-guide/filters.html#pattern-replace-filter)
* [Synonym Graph Filter](https://solr.apache.org/guide/solr/latest/indexing-guide/filters.html#synonym-graph-filter)
* [Path Hierarchy Tokenizer](https://solr.apache.org/guide/solr/latest/indexing-guide/tokenizers.html#path-hierarchy-tokenizer)

as compared to the ElasticSearch examples in the book.

For the most part, the XML configuration maps fairly cleanly to the schema API
here.

### A Note on Nested Documents

Note that the TMDB data set includes nested documents (e.g. cast, location).
Although Solr [can index nested
documents](https://solr.apache.org/guide/solr/latest/indexing-guide/indexing-nested-documents.html)
it requires some more work, and nothing in Chapters 3 or 4 require the data from
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

To start a pry session where you can query Solr:

```
docker-compose run --rm query
```

This will load `query.rb` and start pry.

Some things you might try doing:

```ruby
params = {q: "basketball with cartoon aliens", defType: "edismax", qf: "title^10 overview"}
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

