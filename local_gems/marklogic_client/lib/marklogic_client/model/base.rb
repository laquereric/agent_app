require "active_support/concern"
require "active_model"
require "securerandom"

module Marklogic
  module Model
    # Base class for creating MarkLogic-backed models, providing an interface similar to ActiveRecord.
    # It includes functionality for defining attributes, CRUD operations (Create, Read, Update, Delete),
    # basic search, and change tracking via `ActiveModel::Dirty`.
    #
    # Models inheriting from `Marklogic::Model::Base` interact with the MarkLogic server
    # through the `Marklogic::Client::API`.
    #
    # @example Defining a Model
    #   class Article < Marklogic::Model::Base
    #     attribute :title, :string
    #     attribute :body, :text
    #     attribute :published_at, :datetime
    #   end
    #
    # @example Creating an Instance
    #   article = Article.new(title: "My First Article", body: "Hello World!")
    #   article.save
    #   puts "Article URI: #{article.uri}"
    #
    # @example Finding an Instance
    #   found_article = Article.find(article.uri)
    #   puts "Found: #{found_article.title}"
    class Base
      extend ActiveSupport::Concern # For features like ClassMethods, included blocks
      include ActiveModel::Model # For basic model features like attributes, validation (optional)
      include ActiveModel::Attributes # For attribute handling (e.g., `attribute :name, :string`)
      include ActiveModel::Dirty # For tracking attribute changes (e.g., `title_changed?`)

      # @!attribute [r] uri
      #   @return [String, nil] The URI of the document in MarkLogic. Nil for new, unsaved records.
      attr_reader :uri

      # @!attribute [r] persisted
      #   @return [Boolean] True if the record has been persisted to MarkLogic, false otherwise.
      attr_reader :persisted
      alias :persisted? :persisted

      # --- Class Methods ---
      module ClassMethods
        # Provides access to the MarkLogic API client instance for this model class.
        # Lazily initializes a new `Marklogic::Client::API` instance if one doesn't exist.
        # @return [Marklogic::Client::API] The API client instance.
        def db_client
          # Each model class can have its own client, or they can share one based on global config.
          # For simplicity, this uses a new client per class, which in turn uses global config by default.
          @db_client ||= Marklogic::Client::API.new
        end

        # Finds a document by its URI and returns an instance of the model.
        # @param uri [String] The URI of the document to find.
        # @return [Marklogic::Model::Base] An instance of the model populated with data from the document.
        # @raise [Marklogic::Model::RecordNotFound] if the document is not found (HTTP 404).
        # @raise [Marklogic::Client::APIError] for other API errors (e.g., server errors, parsing issues).
        def find(uri)
          response = db_client.read_document(uri, format: :json)
          # API class now handles raising APIError for non-2xx, including AuthenticationError
          # We only need to parse if successful (which it will be if we reach here)
          data = JSON.parse(response.body)
          new(data.merge(uri: uri, persisted: true))
        rescue Marklogic::Client::APIError => e
          # Specifically translate a 404 from the API layer into RecordNotFound for the model layer
          if e.response_code == 404
            raise Marklogic::Model::RecordNotFound, "Document not found at URI: #{uri}"
          else
            raise # Re-raise other APIErrors (e.g., 500, auth errors, or JSON parse errors from API layer)
          end
        rescue JSON::ParserError => e # Should ideally be caught by API layer, but as a fallback
          raise Marklogic::Client::APIError, "Failed to parse JSON response from MarkLogic: #{e.message}", nil, response&.body
        end

        # Creates a new instance of the model with the given attributes and saves it to MarkLogic.
        # @param attributes [Hash] A hash of attributes for the new record.
        # @return [Marklogic::Model::Base] The newly created and persisted model instance.
        #   If saving fails, the instance is returned but `persisted?` will be false.
        def create(attributes = {})
          instance = new(attributes)
          instance.save
          instance
        end

        # Performs a basic search using the MarkLogic search API and maps results to model instances.
        # This is a simplified implementation. For complex queries or result processing,
        # consider using the `db_client.search` method directly or extending this method.
        # @param query_string [String] The search query string.
        # @param options [Hash] Search options to pass to the API (e.g., `pageLength: 10`, `options: 'my-search-options'`).
        #   `format: :json` is typically used by default for model mapping.
        # @return [Array<Marklogic::Model::Base>] An array of model instances matching the search query.
        # @raise [Marklogic::Client::APIError] if the search API call fails.
        def where(query_string, options: { format: :json })
          merged_options = { format: :json }.merge(options) # Ensure JSON for model mapping
          response = db_client.search(query_string, options: merged_options)
          # API class handles non-2xx responses by raising errors
          results = JSON.parse(response.body)

          (results["results"] || []).map do |result_doc|
            doc_uri = result_doc["uri"]
            if result_doc["content"] && result_doc["format"] == "json"
              # If content is directly in search result (e.g., from extract-document-data)
              new(result_doc["content"].merge(uri: doc_uri, persisted: true))
            elsif doc_uri
              # If only URI is present, fetch the full document (N+1 query potential)
              # This path is less efficient and depends on search configuration.
              begin
                find(doc_uri) # Use existing find method which handles errors
              rescue Marklogic::Model::RecordNotFound, Marklogic::Client::APIError => e
                # Log or handle the error for this specific document, then skip it
                # Example: Marklogic::Client.logger.warn "Could not load document #{doc_uri} from search results: #{e.message}"
                nil
              end
            else
              nil # Skip if no URI or suitable content
            end
          end.compact
        rescue JSON::ParserError => e
          raise Marklogic::Client::APIError, "Failed to parse JSON search response: #{e.message}", nil, response&.body
        end
      end

      # --- Instance Methods ---

      # Initializes a new model instance.
      # @param attributes [Hash] A hash of attributes to set on the new instance.
      #   Special keys `:uri` and `:persisted` are handled separately and not passed to `assign_attributes`.
      def initialize(attributes = {})
        super() # Important for ActiveModel::Attributes and ActiveModel::Model initialization

        # Extract special attributes before passing to ActiveModel's assign_attributes
        @uri = attributes.delete(:uri)
        @persisted = attributes.delete(:persisted) || false

        assign_attributes(attributes) # Assign the rest of the attributes

        @previously_changed = {} # For ActiveModel::Dirty
        clear_changes_information # From ActiveModel::Dirty, initialize dirty tracking
      end

      # Assigns a hash of attributes to the model.
      # This method is provided by `ActiveModel::Attributes`.
      # @param new_attributes [Hash] The attributes to assign.
      def assign_attributes(new_attributes)
        super(new_attributes) if new_attributes # From ActiveModel::Attributes
      end

      # Returns a hash of the model's attributes and their current values.
      # This relies on `ActiveModel::Attributes` and `attribute_names`.
      # @return [Hash{Symbol => Object}] A hash of attribute names to values.
      def attributes
        attrs = {}
        self.class.attribute_names.each do |name|
          attrs[name.to_sym] = send(name)
        end
        attrs
      end

      # Saves the model instance to MarkLogic.
      # If the record is new, it generates a URI and creates the document.
      # If the record is persisted, it updates the existing document.
      # Uses `ActiveModel::Dirty` to track changes and clear them upon successful save.
      # @return [Boolean] True if the save was successful, false otherwise.
      def save
        # Optional: Add validation hook here if using ActiveModel::Validations
        # return false unless valid?

        @uri ||= generate_uri unless persisted? # Generate URI only for new records before first save

        doc_attributes = attributes_for_persistence

        # The API client's write_document method will raise an APIError on failure.
        self.class.db_client.write_document(@uri, doc_attributes, format: :json)

        @persisted = true
        changes_applied # From ActiveModel::Dirty: commit changes, clear dirty info
        true
      rescue Marklogic::Client::APIError => e
        # Optional: Populate ActiveModel::Errors if using validations
        # errors.add(:base, "Failed to save document: #{e.message}")
        false
      end

      # Updates the model instance with new attributes and saves it to MarkLogic.
      # @param new_attributes [Hash] The attributes to update.
      # @return [Boolean] True if the update and save were successful, false otherwise.
      def update(new_attributes)
        assign_attributes(new_attributes)
        save
      end

      # Deletes the document from MarkLogic.
      # The instance is marked as not persisted and its changes are cleared.
      # @return [Boolean] True if deletion was successful, false otherwise.
      #   Returns false if the record was not persisted to begin with.
      def destroy
        return false unless persisted?

        # The API client's delete_document method will raise an APIError on failure.
        self.class.db_client.delete_document(@uri)

        @persisted = false
        # Consider what to do with attributes and dirty tracking after destroy.
        # ActiveRecord freezes the object. Here, we clear changes.
        @previously_changed = changes # Store changes before clearing, if needed for callbacks
        clear_changes_information
        true
      rescue Marklogic::Client::APIError => e
        # Optional: Populate ActiveModel::Errors
        # errors.add(:base, "Failed to delete document: #{e.message}")
        false
      end

      private

      # Generates a new URI for a document.
      # This default implementation creates a URI based on the model's class name and a UUID.
      # Override this method in subclasses for custom URI generation strategies.
      # @return [String] A new document URI.
      def generate_uri
        # Use class name, downcased, and without module scoping for a cleaner path segment.
        klass_name_segment = self.class.name&.split("::")&.last&.downcase || "document"
        "/documents/#{klass_name_segment}/#{SecureRandom.uuid}.json"
      end

      # Returns a hash of attributes that should be persisted to MarkLogic.
      # By default, this returns all defined model attributes.
      # Override this method if you need to transform or select attributes before saving.
      # @return [Hash] The attributes to be persisted.
      def attributes_for_persistence
        attributes
      end
    end
  end
end

