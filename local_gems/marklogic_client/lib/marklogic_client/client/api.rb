require "json" # For parsing JSON responses

module Marklogic
  module Client
    # The API class provides a higher-level interface to the MarkLogic REST API.
    # It uses an instance of `Marklogic::Client::Connection` to communicate with the server.
    # This class offers methods for common MarkLogic operations such as document CRUD,
    # search, and evaluation of XQuery or Server-Side JavaScript.
    #
    # @example Basic Usage
    #   api = Marklogic::Client::API.new
    #   # Assuming Marklogic::Client is configured
    #   response = api.read_document("/my/doc.json", format: :json)
    #   puts JSON.parse(response.body) if response.is_a?(Net::HTTPOK)
    class API
      # @!attribute [r] connection
      #   @return [Marklogic::Client::Connection] The connection object used to communicate with MarkLogic.
      attr_reader :connection

      # Initializes a new API client.
      # @param connection [Marklogic::Client::Connection] An existing connection object.
      #   If not provided, a new connection is created using the global configuration.
      def initialize(connection = Marklogic::Client::Connection.new)
        @connection = connection
      end

      # Writes (creates or updates) a document in MarkLogic.
      # See MarkLogic REST API: PUT /v1/documents
      # @param uri [String] The URI of the document to write.
      # @param document [String, Hash, IO] The content of the document.
      #   If a Hash is provided and format is :json (or guessed as JSON), it will be converted to a JSON string.
      # @param collections [Array<String>, String, nil] A list of collections to add the document to.
      # @param permissions [Array<Hash>, nil] An array of permission hashes (e.g., `[{role_name: "app-user", capabilities: ["read", "update"]}]`).
      # @param format [Symbol, nil] The format of the document (:json, :xml, :text, :binary). Guessed if nil.
      # @param txid [String, nil] An optional transaction ID if this operation is part of a multi-statement transaction.
      # @return [Net::HTTPResponse] The HTTP response from MarkLogic.
      # @raise [Marklogic::Client::APIError] if the server returns an error status code (4xx or 5xx).
      # @raise [Marklogic::Client::AuthenticationError] if authentication fails (401).
      def write_document(uri, document, collections: nil, permissions: nil, format: nil, txid: nil)
        params = {}
        params[:collection] = Array(collections).join(",") if collections
        if permissions
          permissions.each do |perm|
            # Ensure perm is a hash with :role_name and :capabilities
            if perm.is_a?(Hash) && perm.key?(:role_name) && perm.key?(:capabilities)
              params["perm:#{perm[:role_name]}"] = Array(perm[:capabilities]).join(",")
            else
              # Log or raise an error for malformed permission
            end
          end
        end
        params[:format] = format.to_s if format
        params[:txid] = txid if txid

        content_type = case format
                       when :json then "application/json"
                       when :xml  then "application/xml"
                       when :text then "text/plain"
                       when :binary then "application/octet-stream"
                       else
                         document.is_a?(Hash) ? "application/json" : "application/xml" # Guess or default
                       end

        body = document.is_a?(Hash) && content_type == "application/json" ? JSON.dump(document) : document

        headers = { "Content-Type" => content_type }
        # Path needs to be just /v1/documents, uri is a param
        response = connection.put("/v1/documents", body, headers, { uri: uri }.merge(params))
        handle_response(response)
      end

      # Reads a document from MarkLogic.
      # See MarkLogic REST API: GET /v1/documents
      # @param uri [String] The URI of the document to read.
      # @param format [Symbol, nil] The desired format of the returned document (:json, :xml, :text, :binary).
      #   If nil, the server default is used (often based on URI extension or content type).
      # @param txid [String, nil] An optional transaction ID.
      # @return [Net::HTTPResponse] The HTTP response from MarkLogic, containing the document if successful.
      # @raise [Marklogic::Client::APIError] if the server returns an error status code.
      # @raise [Marklogic::Client::AuthenticationError] if authentication fails.
      def read_document(uri, format: nil, txid: nil)
        params = { uri: uri }
        params[:format] = format.to_s if format
        params[:txid] = txid if txid

        response = connection.get("/v1/documents", params)
        handle_response(response)
      end

      # Deletes a document from MarkLogic.
      # See MarkLogic REST API: DELETE /v1/documents
      # @param uri [String] The URI of the document to delete.
      # @param txid [String, nil] An optional transaction ID.
      # @return [Net::HTTPResponse] The HTTP response from MarkLogic.
      # @raise [Marklogic::Client::APIError] if the server returns an error status code.
      # @raise [Marklogic::Client::AuthenticationError] if authentication fails.
      def delete_document(uri, txid: nil)
        params = { uri: uri }
        params[:txid] = txid if txid
        response = connection.delete("/v1/documents", {}, params) # Headers can be empty
        handle_response(response)
      end

      # Performs a search in MarkLogic.
      # See MarkLogic REST API: GET /v1/search or POST /v1/search
      # @param query [String] The search query string (e.g., simple string, structured query XML/JSON).
      # @param options [Hash] A hash of search options (e.g., `format: :json`, `start: 1`, `pageLength: 10`, `options: 'my-options'`).
      # @param txid [String, nil] An optional transaction ID.
      # @return [Net::HTTPResponse] The HTTP response containing search results.
      # @raise [Marklogic::Client::APIError] if the server returns an error status code.
      # @raise [Marklogic::Client::AuthenticationError] if authentication fails.
      def search(query, options: {}, txid: nil)
        params = { q: query }.merge(options)
        params[:txid] = txid if txid
        # Determine Accept header based on requested format, default to JSON
        accept_format = options[:format] || :json
        headers = { "Accept" => accept_format == :xml ? "application/xml" : "application/json" }

        # MarkLogic search can be GET or POST (for larger queries). Defaulting to GET.
        response = connection.get("/v1/search", params, headers)
        handle_response(response)
      end

      # Evaluates XQuery or Server-Side JavaScript code on the MarkLogic server.
      # See MarkLogic REST API: POST /v1/eval
      # @param code [String] The XQuery or JavaScript code to execute.
      # @param type [Symbol] The type of code to execute, either `:xquery` or `:javascript` (default: `:xquery`).
      # @param vars [Hash] A hash of external variables to pass to the code. Keys should be strings or symbols.
      #   Values will be converted to their appropriate XDM representation if possible (e.g. JSON for JS, specific types for XQuery).
      # @param database [String, nil] The name of the database to run the code against. If nil, uses the App Server's default.
      # @param txid [String, nil] An optional transaction ID.
      # @return [Net::HTTPResponse] The HTTP response, which may be multipart/mixed containing results.
      # @raise [Marklogic::Client::APIError] if the server returns an error status code.
      # @raise [Marklogic::Client::AuthenticationError] if authentication fails.
      def eval_code(code, type: :xquery, vars: {}, database: nil, txid: nil)
        # Eval endpoint expects form-urlencoded data
        form_params = {}
        form_params[type == :xquery ? "xquery" : "javascript"] = code
        form_params["vars"] = vars.to_json unless vars.empty? # MarkLogic expects vars as a JSON string for /v1/eval
        form_params["database"] = database if database
        form_params["txid"] = txid if txid

        body = URI.encode_www_form(form_params)
        headers = {
          "Content-Type" => "application/x-www-form-urlencoded",
          "Accept" => "multipart/mixed" # Eval often returns multipart results
        }

        response = connection.post("/v1/eval", body, headers)
        handle_response(response)
      end

      private

      # Handles the HTTP response from MarkLogic, raising errors for non-successful status codes.
      # @param response [Net::HTTPResponse] The HTTP response object.
      # @return [Net::HTTPResponse] The same response object if successful.
      # @raise [Marklogic::Client::AuthenticationError] for 401 errors.
      # @raise [Marklogic::Client::APIError] for other 4xx or 5xx errors.
      def handle_response(response)
        case response.code.to_i
        when 200..299 # Success (200 OK, 201 Created, 204 No Content, etc.)
          response
        when 401
          raise Marklogic::Client::AuthenticationError.new("Authentication failed", response.code.to_i, response.body)
        when 404
          # This is a generic 404 from the API perspective. Specific operations (like find in Model) might interpret this as RecordNotFound.
          raise Marklogic::Client::APIError.new("Resource not found or API endpoint not found", response.code.to_i, response.body)
        else # Other 4xx or 5xx errors
          raise Marklogic::Client::APIError.new("MarkLogic API Error", response.code.to_i, response.body)
        end
      end
    end
  end
end

