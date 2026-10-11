# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RbsSupport::Stdlib, '.roots' do
  let(:roots) { described_class.roots(['forwardable', 'json', 'logger']) }

  it 'maps the top-level names a standard library declares beyond core to it', :aggregate_failures do
    expect(roots.values_at('Forwardable', 'JSON', 'Logger')).to eq(['forwardable', 'json', 'logger'])
    expect(roots).to_not include('Object', 'Hash', 'String')
  end
end
