module Marklogic
  module Client
    # Base error class for all Marklogic::Client specific errors.
    class Error < StandardError; end

    # Raised when there is an issue with the connection to the MarkLogic server,
    # such as a timeout or network problem.
    class ConnectionError < Error; end

    # Raised when authentication with the MarkLogic server fails (e.g., HTTP 401).
    class AuthenticationError < Error; end

    # Raised for general errors returned by the MarkLogic REST API (e.g., HTTP 4xx or 5xx responses).
    # It includes the HTTP response code and body for more detailed error information.
    class APIError < Error
      # @!attribute [r] response_code
      #   @return [Integer, nil] The HTTP response code from the server, if available.
      attr_reader :response_code

      # @!attribute [r] response_body
      #   @return [String, nil] The HTTP response body from the server, if available.
      attr_reader :response_body

      # Initializes a new APIError.
      # @param message [String] The error message.
      # @param response_code [Integer, nil] The HTTP status code from the response.
      # @param response_body [String, nil] The body of the HTTP response.
      def initialize(message, response_code = nil, response_body = nil)
        super(message)
        @response_code = response_code
        @response_body = response_body
      end

      # Provides a more detailed string representation of the error,
      # including the HTTP response code and body if available.
      # @return [String] The detailed error message.
      def to_s
        s = super
        s += " (HTTP #{response_code})" if response_code
        s += "\nResponse: #{response_body}" if response_body && !response_body.empty?
        s
      end
    end
  end

  module Model
    # Base error class for all Marklogic::Model specific errors.
    class Error < StandardError; end

    # Raised when a document cannot be found in MarkLogic, typically when using `find` methods.
    # This is often a result of a 404 response from the MarkLogic server for a specific document URI.
    class RecordNotFound < Error; end
    # Add other model-specific errors if needed, for example:
    # class ValidationError < Error; end
  end
end

