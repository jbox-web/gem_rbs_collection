# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MacroIndex do
  def index(source, known)
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'gem.rb')
      File.write(file, source)
      described_class.new(Set.new(known)).index([file])
    end
  end

  describe 'which methods are macros' do
    let(:known) { [['Gem'], ['Gem', 'Core'], ['Gem', 'Finders'], ['Gem', 'Finders', 'ClassMethods'], ['Gem', 'Base']] }

    let(:source) do
      <<~RUBY
        module Gem
          # A module function: called as Gem::Finders.setup(klass), never from a class body.
          module Finders
            def self.setup(model_class)
              model_class.extend(ClassMethods)
            end

            class << self
              def install(model_class)
                model_class.extend(ClassMethods)
              end
            end
          end

          # A module extended onto a class: its instance methods are macros.
          module Taggable
            def acts_as_gem
              include Core
            end
          end

          # A class: its class methods are macros of its subclasses, its
          # instance methods are not.
          class Base
            def self.has_gem
              include Core
            end

            class << self
              def gem_options
                extend Finders::ClassMethods
              end
            end

            def instance_helper
              extend Finders::ClassMethods
            end
          end
        end
      RUBY
    end

    it 'indexes the instance methods of modules and the class methods of classes only' do
      expect(index(source, known)['macros'].keys).to contain_exactly('acts_as_gem', 'has_gem', 'gem_options')
    end
  end

  describe 'calls to the other methods of its module' do
    let(:source) do
      <<~RUBY
        module Gem
          module Taggable
            def acts_as_gem
              gem_on
            end

            def gem_on
              include Core
            end
          end
        end
      RUBY
    end

    it 'follows them' do
      expect(index(source, [['Gem'], ['Gem', 'Core']])['macros'].fetch('acts_as_gem')['include']).to eq(['::Gem::Core'])
    end
  end

  # Expected values from ActiveSupport 8.1.4's core_ext/class/attribute.rb.
  describe 'class attributes' do
    let(:source) do
      <<~RUBY
        module Gem
          module Macros
            def acts_as_gem
              class_attribute :gem_options, instance_writer: false
            end
          end
        end
      RUBY
    end

    let(:effect) { index(source, [['Gem']])['macros'].fetch('acts_as_gem') }

    it "indexes the methods a macro's class attributes define, options included", :aggregate_failures do
      expect(effect['singleton_methods']).to contain_exactly('gem_options', 'gem_options=', 'gem_options?')
      expect(effect['instance_methods']).to contain_exactly('gem_options', 'gem_options?')
    end
  end
end
