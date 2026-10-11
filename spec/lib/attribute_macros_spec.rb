# frozen_string_literal: true

require 'spec_helper'

# Expected values from ActiveSupport 8.1.4: core_ext/class/attribute.rb,
# core_ext/module/attribute_accessors.rb and configurable.rb.
RSpec.describe AttributeMacros do
  def defined_by(macro, options = {})
    described_class.definitions(macro, :x, options).map { |singleton, name, _| [singleton ? :class : :instance, name] }
  end

  describe 'class_attribute' do
    it 'defines the reader, writer and predicate on the class and its instances' do
      expect(defined_by(:class_attribute)).to contain_exactly(
        %i[class x], %i[class x=], %i[class x?], %i[instance x], %i[instance x=], %i[instance x?]
      )
    end

    it 'defines no predicate with instance_predicate: false' do
      expect(defined_by(:class_attribute, instance_predicate: false)).to contain_exactly(
        %i[class x], %i[class x=], %i[instance x], %i[instance x=]
      )
    end

    it 'defines no instance predicate without an instance reader' do
      expect(defined_by(:class_attribute, instance_reader: false)).to contain_exactly(
        %i[class x], %i[class x=], %i[class x?], %i[instance x=]
      )
    end

    it 'lets instance_reader override instance_accessor: false' do
      expect(defined_by(:class_attribute, instance_accessor: false, instance_reader: true)).to contain_exactly(
        %i[class x], %i[class x=], %i[class x?], %i[instance x], %i[instance x?]
      )
    end
  end

  describe 'mattr_* and config_accessor' do
    it 'defines a reader, on the instances unless disabled', :aggregate_failures do
      expect(defined_by(:mattr_reader)).to contain_exactly(%i[class x], %i[instance x])
      expect(defined_by(:cattr_reader, instance_reader: false)).to contain_exactly(%i[class x])
    end

    it 'defines a writer, on the instances unless disabled', :aggregate_failures do
      expect(defined_by(:mattr_writer)).to contain_exactly(%i[class x=], %i[instance x=])
      expect(defined_by(:cattr_writer, instance_accessor: false)).to contain_exactly(%i[class x=])
    end

    it 'defines both with an accessor, each disabled on its own', :aggregate_failures do
      expect(defined_by(:mattr_accessor, instance_writer: false)).to contain_exactly(
        %i[class x], %i[class x=], %i[instance x]
      )
      expect(defined_by(:config_accessor, instance_accessor: false)).to contain_exactly(%i[class x], %i[class x=])
    end
  end
end
