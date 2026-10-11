# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RbsSupport, '.write_atomically' do
  let(:directory) { Dir.mktmpdir }
  let(:path) { File.join(directory, 'gem-generated.rbs') }

  before { File.write(path, "previous\n") }

  after { FileUtils.rm_rf(directory) }

  it 'replaces the file with what the block writes', :aggregate_failures do
    described_class.write_atomically(path) { |io| io.puts 'next' }

    expect(File.read(path)).to eq("next\n")
    expect(Dir.children(directory)).to eq(['gem-generated.rbs'])
  end

  describe 'when the block raises' do
    def interrupted_write
      RbsSupport.write_atomically(path) do |io|
        io.puts 'half'
        raise 'interrupted'
      end
    end

    it 'leaves the previous file whole', :aggregate_failures do
      expect { interrupted_write }.to raise_error('interrupted')
      expect(File.read(path)).to eq("previous\n")
      expect(Dir.children(directory)).to eq(['gem-generated.rbs'])
    end
  end
end
