# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RbsSupport::Stdlib, '.dependencies' do
  let(:declarations) do
    RbsSupport.parse(<<~RBS)
      module Faraday
        module FlatParamsEncoder
          extend ::Forwardable

          def self.encode: (::Hash[::String, untyped] params) -> ::String
        end

        class Response < ::Object
          def body: () -> (::JSON::State | ::Logger)?
          def each: () { (::Faraday::Response) -> void } -> void
        end

        LOGGER: ::Logger
      end
    RBS
  end

  let(:roots) { { 'Forwardable' => 'forwardable', 'JSON' => 'json', 'Logger' => 'logger', 'Set' => 'set' } }

  it 'lists the standard libraries whose top-level names the declarations use' do
    expect(described_class.dependencies(declarations, roots)).to eq(['forwardable', 'json', 'logger'])
  end
end
