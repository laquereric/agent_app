# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

# A dummy model for testing Marklogic::Model::Base
class TestDocument < Marklogic::Model::Base
  attribute :title, :string
  attribute :body, :string
  attribute :published_on, :date
  attribute :views, :integer
end

# Another dummy model for different URI generation
class Article < Marklogic::Model::Base
  attribute :headline, :string
  attribute :content, :string
end

RSpec.describe Marklogic::Model::Base do
  let(:config) do
    Marklogic::Client::Configuration.new.tap do |c|
      c.host = "ml_model_host"
      c.port = 8008
      c.username = "ml_model_user"
      c.password = "ml_model_pass"
    end
  end
  let(:connection) { Marklogic::Client::Connection.new(config) }
  let!(:mock_api_client) { Marklogic::Client::API.new(connection) }
  let(:base_url) { "http://ml_model_user:ml_model_pass@ml_model_host:8008" }

  before do
    WebMock.disable_net_connect!(allow_localhost: true)
    # Stub the db_client class method to return our mock_api_client
    allow(TestDocument).to receive(:db_client).and_return(mock_api_client)
    allow(Article).to receive(:db_client).and_return(mock_api_client)

    # Reset configuration for Marklogic::Client to avoid interference between tests
    Marklogic::Client.instance_variable_set(:@configuration, nil)
    Marklogic::Client.configure do |c|
      c.host = config.host
      c.port = config.port
      c.username = config.username
      c.password = config.password
    end
  end

  after do
    connection.shutdown
    Marklogic::Client.instance_variable_set(:@configuration, nil) # Clean up global config
  end

  describe ".attribute" do
    it "defines attributes on the model" do
      doc = TestDocument.new(title: "Hello", views: 100)
      expect(doc.title).to eq("Hello")
      expect(doc.views).to eq(100)
    end

    it "handles type casting for attributes" do
      doc = TestDocument.new(published_on: "2023-01-01", views: "150")
      expect(doc.published_on).to be_a(Date)
      expect(doc.published_on).to eq(Date.parse("2023-01-01"))
      expect(doc.views).to be_a(Integer)
      expect(doc.views).to eq(150)
    end
  end

  describe "#initialize" do
    it "initializes with attributes" do
      doc = TestDocument.new(title: "My Doc", body: "Content")
      expect(doc.title).to eq("My Doc")
      expect(doc.body).to eq("Content")
      expect(doc.persisted?).to be false
      expect(doc.uri).to be_nil
    end

    it "initializes a persisted record with a URI" do
      doc = TestDocument.new(title: "Existing", uri: "/docs/1.json", persisted: true)
      expect(doc.title).to eq("Existing")
      expect(doc.persisted?).to be true
      expect(doc.uri).to eq("/docs/1.json")
    end
  end

  describe ".find" do
    let(:doc_uri) { "/test/docs/existing_doc.json" }
    let(:doc_content) { { title: "Found Me!", body: "I was in the database." } }

    it "finds a document by URI and instantiates a model" do
      stub_request(:get, "#{base_url}/v1/documents?uri=#{doc_uri}&format=json")
        .to_return(status: 200, body: doc_content.to_json, headers: { "Content-Type" => "application/json" })

      doc = TestDocument.find(doc_uri)

      expect(doc).to be_a(TestDocument)
      expect(doc.title).to eq("Found Me!")
      expect(doc.body).to eq("I was in the database.")
      expect(doc.uri).to eq(doc_uri)
      expect(doc.persisted?).to be true
    end

    it "raises RecordNotFound if the document is not found (404)" do
      stub_request(:get, "#{base_url}/v1/documents?uri=/test/docs/notfound.json&format=json")
        .to_return(status: 404, body: "Document not found")

      expect {
        TestDocument.find("/test/docs/notfound.json")
      }.to raise_error(Marklogic::Model::RecordNotFound, /Document not found at URI: \/test\/docs\/notfound.json/)
    end

    it "raises APIError for other server errors" do
      stub_request(:get, "#{base_url}/v1/documents?uri=/test/docs/error.json&format=json")
        .to_return(status: 500, body: "Server Error")

      expect {
        TestDocument.find("/test/docs/error.json")
      }.to raise_error(Marklogic::Client::APIError, /MarkLogic API Error \(HTTP 500\)/)
    end

    it "raises APIError on JSON parsing error" do
      stub_request(:get, "#{base_url}/v1/documents?uri=#{doc_uri}&format=json")
        .to_return(status: 200, body: "invalid json", headers: { "Content-Type" => "application/json" })
      expect {
        TestDocument.find(doc_uri)
      }.to raise_error(Marklogic::Client::APIError, /Failed to parse JSON response/)
    end
  end

  describe ".create" do
    let(:attributes) { { title: "New Document", body: "To be created." } }

    it "initializes, saves, and returns a new instance" do
      # Stub the URI generation and the write_document call
      allow(SecureRandom).to receive(:uuid).and_return("test-uuid")
      expected_uri = "/documents/testdocument/test-uuid.json"

      stub_request(:put, "#{base_url}/v1/documents?uri=#{expected_uri}&format=json")
        .with(body: JSON.dump(attributes))
        .to_return(status: 201)

      doc = TestDocument.create(attributes)

      expect(doc).to be_a(TestDocument)
      expect(doc.title).to eq("New Document")
      expect(doc.persisted?).to be true
      expect(doc.uri).to eq(expected_uri)
    end

    it "returns the instance even if save fails (persisted? will be false)" do
       stub_request(:put, /#{base_url}\/v1\/documents/).to_return(status: 500)
       doc = TestDocument.create(attributes)
       expect(doc.persisted?).to be false
    end
  end

  describe "#save" do
    context "for a new record" do
      let(:doc) { TestDocument.new(title: "Fresh Doc", body: "Needs saving") }

      it "generates a URI, PUTs the document, and marks as persisted" do
        allow(SecureRandom).to receive(:uuid).and_return("save-uuid")
        expected_uri = "/documents/testdocument/save-uuid.json"

        stub_request(:put, "#{base_url}/v1/documents?uri=#{expected_uri}&format=json")
          .with(body: JSON.dump({ title: "Fresh Doc", body: "Needs saving", published_on: nil, views: nil }))
          .to_return(status: 201)

        expect(doc.save).to be true
        expect(doc.uri).to eq(expected_uri)
        expect(doc.persisted?).to be true
      end

      it "uses a different URI pattern for a different model" do
        article = Article.new(headline: "News")
        allow(SecureRandom).to receive(:uuid).and_return("article-uuid")
        expected_uri = "/documents/article/article-uuid.json"
        stub_request(:put, "#{base_url}/v1/documents?uri=#{expected_uri}&format=json")
          .to_return(status: 201)
        expect(article.save).to be true
        expect(article.uri).to eq(expected_uri)
      end

      it "returns false if API call fails" do
        allow(SecureRandom).to receive(:uuid).and_return("fail-uuid")
        expected_uri = "/documents/testdocument/fail-uuid.json"
        stub_request(:put, "#{base_url}/v1/documents?uri=#{expected_uri}&format=json").to_return(status: 500)
        expect(doc.save).to be false
        expect(doc.persisted?).to be false
      end
    end

    context "for an existing record" do
      let(:doc_uri) { "/my/existing_doc.json" }
      let(:doc) { TestDocument.new(title: "Old Doc", body: "Original content", uri: doc_uri, persisted: true) }

      it "PUTs the document to its existing URI and remains persisted" do
        doc.title = "Updated Doc"
        stub_request(:put, "#{base_url}/v1/documents?uri=#{doc_uri}&format=json")
          .with(body: JSON.dump({ title: "Updated Doc", body: "Original content", published_on: nil, views: nil }))
          .to_return(status: 204) # MarkLogic often returns 204 for updates

        expect(doc.save).to be true
        expect(doc.uri).to eq(doc_uri)
        expect(doc.persisted?).to be true
      end
    end
  end

  describe "#update" do
    let(:doc_uri) { "/my/update_doc.json" }
    let(:doc) { TestDocument.new(title: "Initial Title", uri: doc_uri, persisted: true) }

    it "assigns attributes and saves the record" do
      stub_request(:put, "#{base_url}/v1/documents?uri=#{doc_uri}&format=json")
        .with(body: JSON.dump({ title: "New Title", body: "New Body", published_on: nil, views: nil }))
        .to_return(status: 204)

      expect(doc.update(title: "New Title", body: "New Body")).to be true
      expect(doc.title).to eq("New Title")
      expect(doc.body).to eq("New Body")
      expect(doc.persisted?).to be true
    end
  end

  describe "#destroy" do
    let(:doc_uri) { "/my/destroy_doc.json" }

    context "when record is persisted" do
      let(:doc) { TestDocument.new(title: "To Be Deleted", uri: doc_uri, persisted: true) }

      it "sends a DELETE request and marks as not persisted" do
        stub_request(:delete, "#{base_url}/v1/documents?uri=#{doc_uri}")
          .to_return(status: 204)

        expect(doc.destroy).to be true
        expect(doc.persisted?).to be false
      end

      it "returns false if API call fails" do
        stub_request(:delete, "#{base_url}/v1/documents?uri=#{doc_uri}").to_return(status: 500)
        expect(doc.destroy).to be false
        expect(doc.persisted?).to be true # Should remain persisted if delete fails
      end
    end

    context "when record is not persisted" do
      let(:doc) { TestDocument.new(title: "Not Saved Yet") }
      it "returns false and does not make an API call" do
        expect(doc.destroy).to be false
        expect(WebMock).not_to have_requested(:delete, /#{base_url}/)
      end
    end
  end

  describe ".where (basic search)" do
    let(:query_string) { "searchTerm" }
    let(:search_result_item1) { { "uri" => "/results/doc1.json", "format" => "json", "content" => { "title" => "Result 1" } } }
    let(:search_result_item2) { { "uri" => "/results/doc2.json", "format" => "json", "content" => { "title" => "Result 2" } } }
    let(:search_response_body) { { "results" => [search_result_item1, search_result_item2] }.to_json }

    it "performs a search and maps results to model instances" do
      stub_request(:get, "#{base_url}/v1/search?q=#{query_string}&format=json")
        .to_return(status: 200, body: search_response_body, headers: { "Content-Type" => "application/json" })

      # If search results don't contain full content, .where might make N+1 GETs
      # For this test, we assume content is in the search result as per the refined Model::Base

      documents = TestDocument.where(query_string)

      expect(documents.size).to eq(2)
      expect(documents.first).to be_a(TestDocument)
      expect(documents.first.title).to eq("Result 1")
      expect(documents.first.uri).to eq("/results/doc1.json")
      expect(documents.first.persisted?).to be true
      expect(documents.last.title).to eq("Result 2")
    end

    it "returns an empty array if search fails or returns no results" do
      stub_request(:get, "#{base_url}/v1/search?q=#{query_string}&format=json")
        .to_return(status: 200, body: { "results" => [] }.to_json, headers: { "Content-Type" => "application/json" })
      expect(TestDocument.where(query_string)).to be_empty

      stub_request(:get, "#{base_url}/v1/search?q=other&format=json").to_return(status: 500)
      expect { TestDocument.where("other") }.to raise_error(Marklogic::Client::APIError)
    end

    context "when search result items need individual fetching" do
      let(:search_result_item_no_content) { { "uri" => "/results/doc3.json", "format" => "text" } } # No direct content
      let(:search_response_body_no_content) { { "results" => [search_result_item_no_content] }.to_json }
      let(:doc3_content) { { "title" => "Fetched Separately" }.to_json }

      it "fetches documents individually if content not in search results" do
        stub_request(:get, "#{base_url}/v1/search?q=fetchQuery&format=json")
          .to_return(status: 200, body: search_response_body_no_content, headers: { "Content-Type" => "application/json" })
        stub_request(:get, "#{base_url}/v1/documents?uri=/results/doc3.json&format=json")
          .to_return(status: 200, body: doc3_content, headers: { "Content-Type" => "application/json" })

        documents = TestDocument.where("fetchQuery")
        expect(documents.size).to eq(1)
        expect(documents.first.title).to eq("Fetched Separately")
      end
    end
  end

  describe "ActiveModel::Dirty tracking" do
    let(:doc) { TestDocument.new(title: "Original Title", views: 10) }

    it "tracks changes to attributes" do
      expect(doc.changed?).to be false
      doc.title = "New Title"
      expect(doc.changed?).to be true
      expect(doc.changes).to eq({ "title" => ["Original Title", "New Title"] })
      expect(doc.title_changed?).to be true
      expect(doc.title_was).to eq("Original Title")
    end

    it "clears changes after save" do
      allow(SecureRandom).to receive(:uuid).and_return("dirty-uuid")
      stub_request(:put, /#{base_url}\/v1\/documents/).to_return(status: 201)
      doc.title = "Changed for Save"
      expect(doc.changed?).to be true
      doc.save
      expect(doc.changed?).to be false
      expect(doc.changes).to be_empty
    end
  end
end

