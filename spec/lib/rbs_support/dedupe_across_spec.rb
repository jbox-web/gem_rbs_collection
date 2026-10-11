# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RbsSupport, '.dedupe_across' do
  let(:existing) do
    described_class.parse(<<~RBS)
      module ActiveJob
        module QueueAdapters
          class SidekiqAdapter
            class JobWrapper
            end
          end
        end
      end

      module Rack
        VERSION: String
      end
    RBS
  end

  let(:generated) do
    { 'sidekiq' => described_class.parse(<<~RBS) }
      module ActiveJob
        module QueueAdapters
          class SidekiqAdapter
            JobWrapper: untyped
            SOME: Integer
          end
        end
      end

      module Rack
        VERSION: String
      end
    RBS
  end

  let(:containers) do
    [['ActiveJob'], ['ActiveJob', 'QueueAdapters'], ['ActiveJob', 'QueueAdapters', 'SidekiqAdapter'], ['Rack']]
  end

  let(:result) { described_class.dedupe_across(generated, existing).fetch('sidekiq') }

  it 'drops what the gems not regenerated this run already declare', :aggregate_failures do
    expect(described_class.constant_paths(result)).to eq([['ActiveJob', 'QueueAdapters', 'SidekiqAdapter', 'SOME']])
    expect(described_class.container_names(result).keys).to eq(containers)
  end
end
