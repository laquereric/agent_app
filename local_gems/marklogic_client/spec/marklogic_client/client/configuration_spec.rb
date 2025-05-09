# frozen_string_literal: true

require "spec_helper"

RSpec.describe Marklogic::Client::Configuration do
  describe "#initialize" do
    it "sets default values" do
      config = described_class.new
      expect(config.host).to eq("localhost")
      expect(config.port).to eq(8000)
      expect(config.username).to be_nil
      expect(config.password).to be_nil
      expect(config.auth_type).to eq(:digest)
    end
  end

  describe ".configure" do
    before do
      # Reset configuration before each test to avoid interference
      Marklogic::Client.instance_variable_set(:@configuration, nil)
    end

    it "allows configuration through a block" do
      Marklogic::Client.configure do |config|
        config.host = "testhost"
        config.port = 1234
        config.username = "testuser"
        config.password = "testpass"
        config.auth_type = :basic
      end

      expect(Marklogic::Client.configuration.host).to eq("testhost")
      expect(Marklogic::Client.configuration.port).to eq(1234)
      expect(Marklogic::Client.configuration.username).to eq("testuser")
      expect(Marklogic::Client.configuration.password).to eq("testpass")
      expect(Marklogic::Client.configuration.auth_type).to eq(:basic)
    end

    after do
      # Reset configuration after tests
      Marklogic::Client.instance_variable_set(:@configuration, nil)
    end
  end
end

