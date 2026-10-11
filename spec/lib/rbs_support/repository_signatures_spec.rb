# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RbsSupport, '.repository_signatures' do
  let(:root) { Dir.mktmpdir }

  after { FileUtils.rm_rf(root) }

  def write(path)
    file = File.join(root, 'gems', path)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, '')
    file
  end

  describe 'a regenerated gem with several version directories' do
    let!(:files) do
      {
        stale:           [write('sidekiq/8.1/sidekiq-generated.rbs'), write('sidekiq/8.1/sidekiq.rbs')],
        current_written: write('sidekiq/8.2/sidekiq.rbs'),
        other_generated: write('faraday/2.14/faraday-generated.rbs'),
        other_written:   write('devise/5.0/devise.rbs'),
      }
    end

    it 'leaves out every version directory but the current one', :aggregate_failures do
      hand_written, generated = described_class.repository_signatures(root, { 'sidekiq' => '8.2' })
      expect(hand_written).to contain_exactly(files[:current_written], files[:other_written])
      expect(generated).to contain_exactly(files[:other_generated])
      expect(hand_written + generated).to_not include(*files[:stale])
    end
  end
end
