# frozen_string_literal: true

require_relative "marklogic_client/version"
require_relative "marklogic_client/errors"
require_relative "marklogic_client/client/configuration"
require_relative "marklogic_client/client/connection"
require_relative "marklogic_client/client/api"
require_relative "marklogic_client/model/base"

module Marklogic
  module Client
    class Error < StandardError; end
    # Your code goes here...
  end
end

