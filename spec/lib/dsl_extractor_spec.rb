# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DslExtractor do
  def rbs_for(source)
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'conversion.rb')
      File.write(file, source)
      described_class.new({ ['Model'] => RBS::AST::Declarations::Module }).extract([file]).to_rbs
    end
  end

  # [container path, method name] of every instance method declared.
  def method_keys(declarations, namespace = [])
    declarations.grep(RBS::AST::Declarations::Module).flat_map do |declaration|
      path = namespace + declaration.name.to_s.split('::')
      methods = declaration.members.grep(RBS::AST::Members::MethodDefinition).map { |member| [path, member.name] }
      methods + method_keys(declaration.members, path)
    end
  end

  # Expected values from ActiveSupport 8.1.4's core_ext/class/attribute.rb.
  describe 'class_attribute' do
    let(:source) do
      <<~RUBY
        module Model
          included do
            class_attribute :param_delimiter, instance_reader: false
            class_attribute :callbacks, instance_writer: false, instance_predicate: false
          end
        end
      RUBY
    end

    let(:defined) do
      [
        [['Model'], :param_delimiter=],
        [['Model'], :callbacks],
        [['Model', 'ClassMethods'], :param_delimiter],
        [['Model', 'ClassMethods'], :param_delimiter=],
        [['Model', 'ClassMethods'], :param_delimiter?],
        [['Model', 'ClassMethods'], :callbacks],
        [['Model', 'ClassMethods'], :callbacks=],
      ]
    end

    it 'declares the predicates class_attribute defines, and only those' do
      expect(method_keys(RbsSupport.parse(rbs_for(source)))).to match_array(defined)
    end
  end

  # [container path, mixin kind, module name] of every include / extend declared.
  def mixins(declarations, namespace = [])
    declarations.grep(RBS::AST::Declarations::Module).flat_map do |declaration|
      path = namespace + declaration.name.to_s.split('::')
      own  = declaration.members.filter_map do |member|
        kind = { RBS::AST::Members::Include => :include, RBS::AST::Members::Extend => :extend }[member.class]
        [path, kind, member.name.to_s] if kind
      end
      own + mixins(declaration.members, path)
    end
  end

  # The shape of representable 3.2's lib/representable.rb, whose hook brings
  # Representable::for_collection to every Decorator.
  describe 'a hand-rolled concern extending its base through class_eval' do
    let(:source) do
      <<~RUBY
        module Model
          def self.included(base)
            base.class_eval do
              extend ForCollection
              include Cached
            end
          end
        end
      RUBY
    end

    it 'records the extend on ClassMethods and the include on the module' do
      expect(mixins(RbsSupport.parse(rbs_for(source)))).to contain_exactly(
        [['Model'], :extend, 'ActiveSupport::Concern'],
        [['Model'], :include, 'Cached'],
        [['Model', 'ClassMethods'], :include, 'ForCollection']
      )
    end
  end
end
