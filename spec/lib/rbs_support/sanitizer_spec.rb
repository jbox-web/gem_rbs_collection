# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RbsSupport::Sanitizer do
  # The declarations `rbs` holds, resolved against an environment of their own,
  # then sanitized.
  def sanitize(rbs)
    env      = RbsSupport.tolerant_environment(libraries: [], directories: [], files: [],
                                               sources: { 'generated' => RbsSupport.parse(rbs) })
    resolved = env.sources.select { |source| source.buffer.name == 'generated' }.flat_map(&:declarations)
    described_class.new(env, RbsSupport::Deferred.new).call(resolved)
  end

  # [module, included module] of every include declared.
  def includes(declarations)
    declarations.flat_map do |declaration|
      declaration.members.grep(RBS::AST::Members::Include).map { |member| [declaration.name.to_s, member.name.to_s] }
    end
  end

  # The shape representable 3.2 generates: Representable::JSON includes
  # JSON::Hash, whose hand-rolled hook includes JSON back into its base.
  describe 'two modules including each other' do
    let(:rbs) do
      <<~RBS
        module ::Json
          include ::Json::Hash
        end

        module ::Json::Hash
          include ::Json
        end
      RBS
    end

    it 'drops the include that closes the cycle, and only that one' do
      expect(includes(sanitize(rbs))).to contain_exactly(['::Json::Hash', '::Json'])
    end
  end
end
