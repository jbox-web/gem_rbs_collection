# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RbsSupport, '.tolerant_environment' do
  # A source collides with a file on one nested declaration: sidekiq declares
  # the constant JobWrapper where activejob declares a class.
  let(:file_rbs) do
    <<~RBS
      module ActiveJob
        module QueueAdapters
          class SidekiqAdapter
            class JobWrapper
            end
          end
        end
      end
    RBS
  end

  let(:source_rbs) do
    <<~RBS
      module ActiveJob
        module QueueAdapters
          class SidekiqAdapter
            JobWrapper: untyped

            def enqueue: (untyped job) -> untyped
          end
        end
      end

      module Sidekiq
        VERSION: String
      end
    RBS
  end


  # The environment built from `file_rbs` and `source_rbs`, and what it wrote
  # on stderr.
  def build(file_rbs, source_rbs)
    capturing_stderr do
      Dir.mktmpdir do |dir|
        file = File.join(dir, 'activejob.rbs')
        File.write(file, file_rbs)
        RbsSupport.tolerant_environment(libraries: [], directories: [], files: [file],
                                        sources: { 'sidekiq' => RbsSupport.parse(source_rbs) })
      end
    end
  end

  # What the block returns, and what it wrote on stderr.
  def capturing_stderr
    warnings = StringIO.new
    previous = $stderr
    $stderr  = warnings
    [yield, warnings.string]
  ensure
    $stderr = previous
  end

  def methods_of(env, name)
    entry = env.class_decls.fetch(RBS::TypeName.parse(name))
    entry.each_decl.flat_map(&:members).grep(RBS::AST::Members::MethodDefinition).map(&:name)
  end

  def constants_of(env)
    env.constant_decls.keys.map(&:to_s)
  end

  it 'keeps the rest of a declaration when one nested member collides', :aggregate_failures do
    env, warnings = build(file_rbs, source_rbs)
    expect(warnings).to match(/sidekiq.*::ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper/)
    expect(methods_of(env, '::ActiveJob::QueueAdapters::SidekiqAdapter')).to eq([:enqueue])
    expect(constants_of(env)).to include('::Sidekiq::VERSION')
    expect(constants_of(env)).to_not include('::ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper')
  end

  describe 'a constant the environment already declares' do
    let(:file) { "module Sidekiq\n  VERSION: String\nend\n" }
    let(:source) { "module Sidekiq\n  VERSION: String\n  def self.server?: () -> bool\nend\n" }

    it 'is dropped, its container kept', :aggregate_failures do
      env, warnings = build(file, source)
      expect(warnings).to match(/sidekiq.*::Sidekiq::VERSION/)
      expect(methods_of(env, '::Sidekiq')).to eq([:server?])
    end
  end

  describe 'a container whose kind differs from the existing one' do
    let(:file) { "module Foo\n  class Bar\n  end\nend\n" }
    let(:source) { "module Foo\n  module Bar\n  end\n\n  def self.kept: () -> void\nend\n" }

    it 'is dropped', :aggregate_failures do
      env, warnings = build(file, source)
      expect(warnings).to match(/sidekiq.*::Foo::Bar/)
      expect(env.class_decls.fetch(RBS::TypeName.parse('::Foo::Bar'))).to be_a(RBS::Environment::ClassEntry)
      expect(methods_of(env, '::Foo')).to eq([:kept])
    end
  end
end
