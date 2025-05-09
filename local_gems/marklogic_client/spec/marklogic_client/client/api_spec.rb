# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

RSpec.describe Marklogic::Client::API do
  let(:config) do
    Marklogic::Client::Configuration.new.tap do |c|
      c.host = "ml_host"
      c.port = 8000
      c.username = "ml_user"
      c.password = "ml_pass"
    end
  end
  let(:connection) { Marklogic::Client::Connection.new(config) }
  let(:api) { described_class.new(connection) }
  let(:base_url) { "http://ml_user:ml_pass@ml_host:8000" }

  before do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  after do
    connection.shutdown
  end

  describe "#initialize" do
    it "can be initialized with a connection" do
      expect(api.connection).to eq(connection)
    end

    it "initializes a new connection if none is provided" do
      default_api = described_class.new
      expect(default_api.connection).to be_a(Marklogic::Client::Connection)
      default_api.connection.shutdown
    end
  end

  describe "#write_document" do
    let(:uri) { "/test/doc1.json" }
    let(:document_content) { { title: "Test Document", body: "Hello MarkLogic!" } }

    it "sends a PUT request to create/update a JSON document" do
      stub_request(:put, "#{base_url}/v1/documents?uri=#{uri}")
        .with(
          body: JSON.dump(document_content),
          headers: {
            "Content-Type" => "application/json",
            "User-Agent" => /MarkLogicRubyClient/
          }
        )
        .to_return(status: 201, body: "", headers: {})

      response = api.write_document(uri, document_content, format: :json)
      expect(response.code.to_i).to eq(201)
    end

    it "sends collections and permissions as parameters" do
      collections = ["coll1", "coll2"]
      permissions = [{ role_name: "app-reader", capabilities: ["read"] }]
      stub_request(:put, "#{base_url}/v1/documents?uri=#{uri}&collection=coll1,coll2&perm:app-reader=read")
        .to_return(status: 201)

      api.write_document(uri, document_content, collections: collections, permissions: permissions, format: :json)
      expect(WebMock).to have_requested(:put, "#{base_url}/v1/documents?uri=#{uri}&collection=coll1,coll2&perm:app-reader=read")
    end

    it "handles XML documents" do
      xml_content = "<doc><title>Test XML</title></doc>"
      stub_request(:put, "#{base_url}/v1/documents?uri=/test/doc.xml&format=xml")
        .with(body: xml_content, headers: { "Content-Type" => "application/xml" })
        .to_return(status: 201)
      api.write_document("/test/doc.xml", xml_content, format: :xml)
    end

    it "raises APIError on server error" do
      stub_request(:put, "#{base_url}/v1/documents?uri=#{uri}").to_return(status: 500, body: "Server Error")
      expect { api.write_document(uri, document_content, format: :json) }.to raise_error(Marklogic::Client::APIError, /MarkLogic API Error \(HTTP 500\)/)
    end
  end

  describe "#read_document" do
    let(:uri) { "/test/doc1.json" }
    let(:response_body) { { title: "Test Document" }.to_json }

    it "sends a GET request to read a document" do
      stub_request(:get, "#{base_url}/v1/documents?uri=#{uri}&format=json")
        .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

      response = api.read_document(uri, format: :json)
      expect(response.code.to_i).to eq(200)
      expect(response.body).to eq(response_body)
    end

    it "raises APIError if document not found (404)" do
      stub_request(:get, "#{base_url}/v1/documents?uri=#{uri}&format=json")
        .to_return(status: 404, body: "Not Found")
      expect { api.read_document(uri, format: :json) }.to raise_error(Marklogic::Client::APIError, /Resource not found or API endpoint not found \(HTTP 404\)/)
    end
  end

  describe "#delete_document" do
    let(:uri) { "/test/doc1.json" }

    it "sends a DELETE request to remove a document" do
      stub_request(:delete, "#{base_url}/v1/documents?uri=#{uri}")
        .to_return(status: 204, body: nil)

      response = api.delete_document(uri)
      expect(response.code.to_i).to eq(204)
    end

    it "raises APIError on failure" do
      stub_request(:delete, "#{base_url}/v1/documents?uri=#{uri}")
        .to_return(status: 500, body: "Error")
      expect { api.delete_document(uri) }.to raise_error(Marklogic::Client::APIError)
    end
  end

  describe "#search" do
    let(:query) { "test" }
    let(:search_results) { { results: [{ uri: "/doc1.json" }] }.to_json }

    it "sends a GET request to the search endpoint" do
      stub_request(:get, "#{base_url}/v1/search?q=#{query}&format=json")
        .with(headers: { "Accept" => "application/json" })
        .to_return(status: 200, body: search_results, headers: { "Content-Type" => "application/json" })

      response = api.search(query, options: { format: :json })
      expect(response.code.to_i).to eq(200)
      expect(response.body).to eq(search_results)
    end

    it "allows passing search options" do
      stub_request(:get, "#{base_url}/v1/search?q=#{query}&format=xml&start=1&pageLength=5")
        .with(headers: { "Accept" => "application/xml" })
        .to_return(status: 200, body: "<results/>")
      api.search(query, options: { format: :xml, start: 1, pageLength: 5 })
    end
  end

  describe "#eval_code" do
    let(:xquery_code) { "cts:search(\"hello\")" }
    let(:js_code) { "cts.search(\"hello\")" }
    let(:eval_response_body) { "multipart boundary...<result>value</result>..." }

    it "sends a POST request to eval XQuery" do
      stub_request(:post, "#{base_url}/v1/eval")
        .with(
          body: URI.encode_www_form({ xquery: xquery_code }),
          headers: { "Content-Type" => "application/x-www-form-urlencoded", "Accept" => "multipart/mixed" }
        )
        .to_return(status: 200, body: eval_response_body, headers: { "Content-Type" => "multipart/mixed; boundary=abc" })

      response = api.eval_code(xquery_code, type: :xquery)
      expect(response.code.to_i).to eq(200)
      expect(response.body).to include("<result>value</result>")
    end

    it "sends a POST request to eval JavaScript" do
      stub_request(:post, "#{base_url}/v1/eval")
        .with(body: URI.encode_www_form({ javascript: js_code }))
        .to_return(status: 200, body: eval_response_body)

      api.eval_code(js_code, type: :javascript)
    end

    it "sends variables and database parameters" do
      vars = { myVar: "value" }
      db = "Documents"
      stub_request(:post, "#{base_url}/v1/eval")
        .with(body: URI.encode_www_form({ xquery: xquery_code, vars: vars.to_json, database: db }))
        .to_return(status: 200, body: eval_response_body)

      api.eval_code(xquery_code, type: :xquery, vars: vars, database: db)
    end
  end

  describe "error handling" do
    it "raises AuthenticationError on 401" do
      stub_request(:get, "#{base_url}/v1/some/path").to_return(status: 401, body: "Unauthorized")
      expect { api.read_document("/some/path") }.to raise_error(Marklogic::Client::AuthenticationError, /Authentication failed \(HTTP 401\)/)
    end
  end
end

