require "net/http/persistent"
require "digest"

module Marklogic
  module Client
    # The Connection class is responsible for establishing and managing a persistent HTTP/HTTPS connection
    # to a MarkLogic server. It handles authentication and provides low-level methods for making HTTP requests.
    #
    # It uses `Net::HTTP::Persistent` to maintain an open connection, reducing overhead for multiple requests.
    #
    # @example Creating a new connection
    #   config = Marklogic::Client.configuration
    #   connection = Marklogic::Client::Connection.new(config)
    #   response = connection.get("/v1/ping") # Example GET request
    #   connection.shutdown
    class Connection
      # @!attribute [r] config
      #   @return [Marklogic::Client::Configuration] The configuration object used for this connection.
      attr_reader :config

      # @!attribute [r] http_client
      #   @return [Net::HTTP::Persistent] The persistent HTTP client instance.
      attr_reader :http_client

      # Initializes a new Connection object.
      # @param config [Marklogic::Client::Configuration] The configuration to use for this connection.
      #   Defaults to the global `Marklogic::Client.configuration`.
      def initialize(config = Marklogic::Client.configuration)
        @config = config
        @http_client = Net::HTTP::Persistent.new name: "marklogic_client"
        # Configure http_client further if needed, e.g., SSL, timeouts
        # @http_client.verify_mode = OpenSSL::SSL::VERIFY_PEER if config.port == 443 # Example for SSL
        # @http_client.timeout = 10 # seconds
      end

      # Makes an HTTP request to the MarkLogic server.
      # This is a general-purpose method used by the convenience methods (get, post, etc.).
      #
      # @param method [Symbol, String] The HTTP method (e.g., :get, :post, "PUT").
      # @param path [String] The request path (e.g., "/v1/documents").
      # @param headers [Hash] A hash of HTTP headers to include in the request.
      # @param body [String, IO, nil] The request body.
      # @param params [Hash, nil] URL query parameters.
      # @return [Net::HTTPResponse] The HTTP response object from the server.
      # @raise [ArgumentError] if an unsupported HTTP method is provided.
      # @raise [Marklogic::Client::ConnectionError] if there is a persistent connection error.
      # @raise [Marklogic::Client::Error] for other standard request failures.
      def request(method, path, headers = {}, body = nil, params = nil)
        uri = URI::HTTP.build(host: config.host, port: config.port, path: path)
        uri.query = URI.encode_www_form(params) if params && !params.empty?

        req = case method.to_s.upcase
              when "GET"
                Net::HTTP::Get.new(uri.request_uri)
              when "POST"
                Net::HTTP::Post.new(uri.request_uri)
              when "PUT"
                Net::HTTP::Put.new(uri.request_uri)
              when "DELETE"
                Net::HTTP::Delete.new(uri.request_uri)
              when "HEAD"
                Net::HTTP::Head.new(uri.request_uri)
              else
                raise ArgumentError, "Unsupported HTTP method: #{method}"
              end

        # Add default headers
        req["User-Agent"] = "MarkLogicRubyClient/#{Marklogic::Client::VERSION}"
        req["Content-Type"] ||= "application/json" # Default content type
        req["Accept"] ||= "application/json"      # Default accept type

        headers.each { |key, value| req[key] = value }

        req.body = body if body

        # Authentication
        if config.username && config.password
          case config.auth_type
          when :basic
            req.basic_auth(config.username, config.password)
          when :digest
            # Net::HTTP::Persistent handles digest authentication automatically if the server challenges.
            # We need to ensure the connection is set up to allow this.
            # The `set_auth` method on `Net::HTTP::Persistent` is used to provide credentials for a URI.
            @http_client.set_auth(uri, config.username, config.password)
          else
            raise ArgumentError, "Unsupported auth_type: #{config.auth_type}"
          end
        end

        response = @http_client.request(uri, req)

        response
      rescue Net::HTTP::Persistent::Error => e
        raise Marklogic::Client::ConnectionError, "Connection error: #{e.message} for #{method.to_s.upcase} #{uri}"
      rescue StandardError => e
        # Catching a broader range of errors that might occur during request preparation or execution
        raise Marklogic::Client::Error, "Request failed: #{e.class} - #{e.message} for #{method.to_s.upcase} #{uri}"
      end

      # Convenience method for making a GET request.
      # @param path [String] The request path.
      # @param params [Hash] URL query parameters.
      # @param headers [Hash] HTTP headers.
      # @return [Net::HTTPResponse] The HTTP response.
      def get(path, params = {}, headers = {})
        request(:get, path, headers, nil, params)
      end

      # Convenience method for making a POST request.
      # @param path [String] The request path.
      # @param body [String, IO] The request body.
      # @param headers [Hash] HTTP headers.
      # @return [Net::HTTPResponse] The HTTP response.
      def post(path, body, headers = {})
        request(:post, path, headers, body)
      end

      # Convenience method for making a PUT request.
      # @param path [String] The request path.
      # @param body [String, IO] The request body.
      # @param headers [Hash] HTTP headers.
      # @return [Net::HTTPResponse] The HTTP response.
      def put(path, body, headers = {})
        request(:put, path, headers, body)
      end

      # Convenience method for making a DELETE request.
      # @param path [String] The request path.
      # @param headers [Hash] HTTP headers.
      # @param params [Hash] URL query parameters (less common for DELETE but possible).
      # @return [Net::HTTPResponse] The HTTP response.
      def delete(path, headers = {}, params = {})
        request(:delete, path, headers, nil, params)
      end

      # Convenience method for making a HEAD request.
      # @param path [String] The request path.
      # @param params [Hash] URL query parameters.
      # @param headers [Hash] HTTP headers.
      # @return [Net::HTTPResponse] The HTTP response.
      def head(path, params = {}, headers = {})
        request(:head, path, headers, nil, params)
      end

      # Shuts down the persistent HTTP connection.
      # It is important to call this when the connection is no longer needed to release resources.
      def shutdown
        @http_client.shutdown
      end
    end
  end
end

