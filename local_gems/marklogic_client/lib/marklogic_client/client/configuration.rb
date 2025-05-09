module Marklogic
  module Client
    # Configuration class for the MarkLogic client.
    # Stores connection details such as host, port, username, password, and authentication type.
    #
    # @example Basic Configuration
    #   Marklogic::Client.configure do |config|
    #     config.host = "localhost"
    #     config.port = 8000
    #     config.username = "admin"
    #     config.password = "admin"
    #     config.auth_type = :digest
    #   end
    class Configuration
      # @!attribute [rw] host
      #   @return [String] The hostname or IP address of the MarkLogic server. Defaults to "localhost".
      attr_accessor :host

      # @!attribute [rw] port
      #   @return [Integer] The port number for the MarkLogic App Server. Defaults to 8000.
      attr_accessor :port

      # @!attribute [rw] username
      #   @return [String, nil] The username for authentication. Defaults to nil.
      attr_accessor :username

      # @!attribute [rw] password
      #   @return [String, nil] The password for authentication. Defaults to nil.
      attr_accessor :password

      # @!attribute [rw] auth_type
      #   @return [Symbol] The authentication type to use. Supported values are `:digest` (default) and `:basic`.
      attr_accessor :auth_type

      # Initializes a new Configuration object with default values.
      def initialize
        @host = "localhost"
        @port = 8000 # Default MarkLogic App-Services port
        @username = nil
        @password = nil
        @auth_type = :digest # MarkLogic default
      end
    end

    # Returns the global configuration object for the MarkLogic client.
    # If no configuration has been set, it initializes a new one with default values.
    # @return [Marklogic::Client::Configuration] The global configuration object.
    def self.configuration
      @configuration ||= Configuration.new
    end

    # Allows global configuration of the MarkLogic client.
    # Yields the global configuration object to a block.
    # @yield [configuration] The global configuration object.
    # @example
    #   Marklogic::Client.configure do |config|
    #     config.host = "remote.marklogic.com"
    #   end
    def self.configure
      yield(configuration)
    end
  end
end

