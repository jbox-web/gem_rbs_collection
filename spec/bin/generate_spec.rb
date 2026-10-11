# frozen_string_literal: true

require 'spec_helper'

require 'open3'

# bin/generate's argument handling: every case below stops before running any
# generator, on a directory that does not exist.
RSpec.describe 'bin/generate' do
  def generate(*)
    script = File.expand_path('../../bin/generate', __dir__)
    Open3.capture3({ 'LANG' => 'en_US.UTF-8', 'LC_ALL' => 'en_US.UTF-8' }, 'ruby', script, *)
  end

  it 'rejects a --gem without its source directory with the usage line', :aggregate_failures do
    _, stderr, status = generate('--gem', 'faraday:2.14.0')

    expect(status.exitstatus).to eq(1)
    expect(stderr).to eq("--gem expects NAME:VERSION:DIR, got faraday:2.14.0\n")
  end

  it 'generates the eleven Rails gems beside a --gem when none is named', :aggregate_failures do
    _, stderr, status = generate('--gems-dir', '/nonexistent', '--rails', '8.1.4', '--gem',
                                 'faraday:2.14.0:/nonexistent')

    expect(status.exitstatus).to eq(1)
    expect(stderr).to eq("/nonexistent/activesupport-8.1.4/lib not found\n")
  end

  it 'generates only the Rails gems named' do
    _, stderr, = generate('--gems-dir', '/nonexistent', '--rails', '8.1.4', '--gem', 'faraday:2.14.0:/nonexistent',
                          'railties')

    expect(stderr).to eq("/nonexistent/railties-8.1.4/lib not found\n")
  end
end
