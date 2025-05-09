# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

RSpec.describe Marklogic::Client::Connection do
  let(:config) do
    Marklogic::Client::Configuration.new.tap do |c|
      c.host = "testhost.example.com"
      c.port = 8003
      c.username = "testuser"
      c.password = "testpass"
      c.auth_type = :digest
    end
  end
  let(:connection) { described_class.new(config) }

  before do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  after do
    connection.shutdown
  end

  describe "#initialize" do
    it "initializes with a configuration" do
      expect(connection.config).to eq(config)
      expect(connection.http_client).to be_a(Net::HTTP::Persistent)
    end

    it "uses default configuration if none provided" do
      Marklogic::Client.configure do |c|
        c.host = "default_host"
      end
      conn = described_class.new
      expect(conn.config.host).to eq("default_host")
      Marklogic::Client.instance_variable_set(:@configuration, nil) # cleanup
      conn.shutdown
    end
  end

  describe "#request" do
    let(:base_url) { "http://testuser:testpass@testhost.example.com:8003" }

    context "with GET request" do
      it "makes a GET request to the specified path" do
        stub_request(:get, "#{base_url}/v1/documents?uri=/test.json")
          .to_return(status: 200, body: "{\"message\": \"success\"}", headers: { "Content-Type" => "application/json" })

        response = connection.get("/v1/documents?uri=/test.json")
        expect(response.code.to_i).to eq(200)
        expect(response.body).to eq("{\"message\": \"success\"}")
        expect(WebMock).to have_requested(:get, "#{base_url}/v1/documents?uri=/test.json")
      end
    end

    context "with POST request" do
      it "makes a POST request with a body" do
        stub_request(:post, "#{base_url}/v1/eval")
          .with(body: "xquery=cts:search('test')", headers: { "Content-Type" => "application/x-www-form-urlencoded" })
          .to_return(status: 200, body: "<result>success</result>", headers: { "Content-Type" => "application/xml" })

        response = connection.request(:post, "/v1/eval", { "Content-Type" => "application/x-www-form-urlencoded" }, "xquery=cts:search('test')")
        expect(response.code.to_i).to eq(200)
        expect(response.body).to eq("<result>success</result>")
      end
    end

    context "with PUT request" do
      it "makes a PUT request with a JSON body" do
        stub_request(:put, "#{base_url}/v1/documents?uri=/test.json")
          .with(body: "{\"title\":\"test doc\"}", headers: { "Content-Type" => "application/json" })
          .to_return(status: 201)

        response = connection.put("/v1/documents?uri=/test.json", "{\"title\":\"test doc\"}", { "Content-Type" => "application/json" })
        expect(response.code.to_i).to eq(201)
      end
    end

    context "with DELETE request" do
      it "makes a DELETE request" do
        stub_request(:delete, "#{base_url}/v1/documents?uri=/test.json")
          .to_return(status: 204)

        response = connection.delete("/v1/documents?uri=/test.json")
        expect(response.code.to_i).to eq(204)
      end
    end

    context "with HEAD request" do
      it "makes a HEAD request" do
        stub_request(:head, "#{base_url}/v1/documents?uri=/test.json")
          .to_return(status: 200, headers: { "Content-Type" => "application/json" })

        response = connection.head("/v1/documents?uri=/test.json")
        expect(response.code.to_i).to eq(200)
        expect(response["Content-Type"]).to eq("application/json")
      end
    end

    context "with basic authentication" do
      before do
        config.auth_type = :basic
      end

      it "sends basic auth headers" do
        stub_request(:get, "#{base_url}/v1/ping")
          .with(headers: { "Authorization" => "Basic dGVzdHVzZXI6dGVzdHBhc3M=" }) # testuser:testpass
          .to_return(status: 200, body: "OK")

        connection.get("/v1/ping")
        expect(WebMock).to have_requested(:get, "#{base_url}/v1/ping")
          .with(headers: { "Authorization" => "Basic dGVzdHVzZXI6dGVzdHBhc3M=" })
      end
    end

    # Digest auth is harder to test directly with WebMock without simulating the challenge-response.
    # Net::HTTP::Persistent handles it, so we trust it does its job if configured.
    # A more involved test would require mocking the 401 challenge and verifying the subsequent request.
    context "with digest authentication" do
      it "attempts digest authentication (trusting Net::HTTP::Persistent)" do
        # This test primarily ensures no error is raised during setup for digest.
        # Actual digest flow is complex to mock simply.
        stub_request(:get, "#{base_url}/v1/ping")
          .to_return(status: 200, body: "OK") # Assume digest auth succeeds

        expect { connection.get("/v1/ping") }.not_to raise_error
      end
    end

    context "when connection fails" do
      it "raises a ConnectionError" do
        stub_request(:get, "#{base_url}/v1/failing").to_timeout
        expect { connection.get("/v1/failing") }.to raise_error(Marklogic::Client::ConnectionError, /Connection error: execution expired/)
      end
    end

    context "with unsupported HTTP method" do
      it "raises an ArgumentError" do
        expect { connection.request(:patch, "/v1/test", {}, "{}") }.to raise_error(ArgumentError, "Unsupported HTTP method: patch")
      end
    end
  end

  describe "#shutdown" do
    it "calls shutdown on the http_client" do
      expect(connection.http_client).to receive(:shutdown)
      connection.shutdown
    end
  end
end

