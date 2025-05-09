# MarkLogicClient

`marklogic_client` is a Ruby gem designed to provide an easy-to-use, ActiveRecord-like interface for interacting with a MarkLogic NoSQL server. It focuses on establishing and utilizing persistent HTTP connections to the MarkLogic REST API for efficient communication.

This gem allows developers to configure connections to their MarkLogic instances, perform CRUD (Create, Read, Update, Delete) operations on documents (JSON, XML, text, binary), execute XQuery and Server-Side JavaScript (SJS) queries, and perform searches. It also includes a base model class that can be inherited to map Ruby objects to documents in MarkLogic, simplifying data manipulation and access.

## Features

*   Persistent HTTP connections to MarkLogic using `Net::HTTP::Persistent`.
*   Configuration for MarkLogic server details (host, port, credentials, authentication type).
*   High-level API for document management (CRUD), search, and code evaluation (XQuery/SJS).
*   An ActiveRecord-like base model (`Marklogic::Model::Base`) for mapping Ruby objects to MarkLogic documents.
*   Support for common MarkLogic REST API features like collections and permissions.
*   Custom error handling for connection and API-specific issues.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "marklogic_client"
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install marklogic_client
```

(Note: This gem is not yet published to RubyGems.org. For now, you would typically install it from a Git repository or a local path if you have the source.)

## Usage

### 1. Configuration

First, configure the connection to your MarkLogic server. This can be done globally:

```ruby
require "marklogic_client"

Marklogic::Client.configure do |config|
  config.host = "your-marklogic-host.com"
  config.port = 8000 # Your MarkLogic App Server port (default is 8000 for HTTP)
  config.username = "your-user"
  config.password = "your-password"
  config.auth_type = :digest # Or :basic
end
```

### 2. Using the API Client Directly

You can use the `Marklogic::Client::API` to interact with the MarkLogic server directly.

```ruby
api_client = Marklogic::Client::API.new

# Write a JSON document
doc_uri = "/my/data/doc1.json"
doc_content = { title: "Hello MarkLogic", body: "This is a test document." }
begin
  response = api_client.write_document(doc_uri, doc_content, collections: ["test_docs"], format: :json)
  puts "Document written successfully! (Status: #{response.code})"
rescue Marklogic::Client::APIError => e
  puts "Error writing document: #{e.message}"
end

# Read a document
begin
  response = api_client.read_document(doc_uri, format: :json)
  if response.code.to_i == 200
    puts "Document content: #{JSON.parse(response.body)}"
  end
rescue Marklogic::Client::APIError => e
  puts "Error reading document: #{e.message}"
end

# Search documents
begin
  response = api_client.search("Hello", options: { format: :json })
  puts "Search results: #{JSON.parse(response.body)}"
rescue Marklogic::Client::APIError => e
  puts "Error searching: #{e.message}"
end

# Execute XQuery
begin
  xquery = 'cts:search("/my/data/*", cts:word-query("MarkLogic"))'
  response = api_client.eval_code(xquery, type: :xquery)
  # Process multipart/mixed response
  puts "XQuery eval response: #{response.body}" # Simplified; requires multipart parsing
rescue Marklogic::Client::APIError => e
  puts "Error evaluating XQuery: #{e.message}"
end
```

### 3. Using Models (ActiveRecord-like)

Define your models by inheriting from `Marklogic::Model::Base`.

```ruby
class Post < Marklogic::Model::Base
  attribute :title, :string
  attribute :author, :string
  attribute :body, :text
  attribute :published_at, :datetime
end

# Create a new post
new_post = Post.new(title: "My First Post", author: "Me", body: "This is exciting!")
if new_post.save
  puts "Post saved! URI: #{new_post.uri}"
else
  puts "Failed to save post."
end

# Find a post by URI
begin
  found_post = Post.find(new_post.uri) # Assuming new_post.uri is available
  puts "Found post: #{found_post.title}"
rescue Marklogic::Model::RecordNotFound
  puts "Post not found."
end

# Update a post
if found_post
  found_post.title = "My Updated Post Title"
  if found_post.save
    puts "Post updated!"
  end
end

# Search for posts (basic example)
# The .where method is a placeholder and needs a robust implementation
# based on how you want to structure search queries (e.g., using a DSL for cts:query).
# For now, it might pass a simple string query.
# results = Post.where("title:Updated")
# results.each do |post|
#   puts "Search result: #{post.title}"
# end

# Delete a post
if found_post&.destroy
  puts "Post deleted."
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/example/marklogic_client](https://github.com/example/marklogic_client). (Please update this URL to the actual repository URL if it's hosted elsewhere).

This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to a code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the MarklogicClient project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/example/marklogic_client/blob/main/CODE_OF_CONDUCT.md). (Please create and link a CODE_OF_CONDUCT.md file).

