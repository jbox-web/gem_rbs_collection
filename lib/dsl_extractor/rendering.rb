# frozen_string_literal: true

class DslExtractor
  # Writes what was extracted as RBS source, nested the way the Ruby source
  # nests its modules, with the superclasses the source names.
  module Rendering
    SHAPES = {
      any:       '(*untyped, **untyped) ?{ (*untyped) -> untyped } -> untyped',
      reader:    '() -> untyped',
      writer:    '(untyped value) -> untyped',
      predicate: '() -> bool',
    }.freeze

    private

      # The superclass a class's source names, kept for the classes the given
      # RBS does not declare: reopened without one, RBS would make them direct
      # subclasses of Object (Invoice would lose ApplicationRecord, an engine
      # Rails::Engine). Only a constant superclass is kept — `Struct.new(…)` or
      # `Migration[8.1]` cannot be written as an RBS superclass name.
      def record_superclass(path, node)
        return unless node.is_a?(Prism::ClassNode) && !@declared.key?(path)

        name = constant_path(node.superclass)
        @supers[path] ||= name.join('::') unless name.empty?
      end

      # The owners, plus — transitively — the superclass of each class they
      # reopen when the source defines it and the given RBS does not declare it:
      # written with its own superclass, it keeps the chain to ApplicationRecord
      # (AuditEvent < AuditRecord < ActiveRecord::Base), where an
      # undeclared superclass would be dropped and the class fall under Object.
      def with_superclasses(owners)
        result  = owners.dup
        pending = owners.flat_map { |owner| (1..owner.size).map { |size| owner.first(size) } }.uniq
        until pending.empty?
          parent = source_superclass(pending.shift)
          next if parent.nil? || result.include?(parent)

          result << parent
          pending << parent
        end
        result
      end

      # Resolves a superclass name the way Ruby does, in the scope enclosing the
      # class, among the classes the source defines and the given RBS does not
      # declare.
      def source_superclass(path)
        name = @supers[path]
        return if name.nil?

        segments = name.split('::')
        (path.size - 1).downto(0).each do |depth|
          candidate = path.first(depth) + segments
          return candidate if @supers.key?(candidate) || (@kinds[candidate] && !@declared.key?(candidate))
        end
        nil
      end

      # ClassMethods is synthesized when the concern declares none.
      def kinds_known?(path)
        (1..path.size).all? { |size| kind(path.first(size)) }
      end

      def kind(path)
        @kinds[path] || (path.last == 'ClassMethods' && @kinds[path[0...-1]] ? RBS::AST::Declarations::Module : nil)
      end

      def render(owner)
        (opening(owner) + body(owner) + closing(owner)).join("\n")
      end

      def opening(owner)
        owner.each_index.map do |depth|
          path    = owner.first(depth + 1)
          keyword = kind(path) == RBS::AST::Declarations::Class ? 'class' : 'module'
          parent  = keyword == 'class' && @supers[path] ? " < #{@supers[path]}" : ''
          "#{'  ' * depth}#{keyword} #{owner[depth]}#{parent}"
        end
      end

      def body(owner)
        indent  = '  ' * owner.size
        mixins  = @includes[owner].uniq.map { |name| "#{indent}include #{name}" }
        mixins += @extends[owner].uniq.map { |name| "#{indent}extend #{name}" }
        mixins + owned_methods(owner).map { |method| "#{indent}#{method_definition(method)}" }
      end

      def owned_methods(owner)
        @methods.select { |method| method.owner == owner }.uniq { |method| [method.singleton, method.name] }
      end

      def method_definition(method)
        "def #{'self.' if method.singleton}#{rbs_name(method.name)}: #{SHAPES.fetch(method.shape)}"
      end

      def closing(owner)
        owner.each_index.to_a.reverse.map { |depth| "#{'  ' * depth}end" }
      end

      # A method name RBS cannot read bare is written between backquotes.
      def rbs_name(name)
        name.to_s.match?(/\A[a-z_][A-Za-z0-9_]*[?!=]?\z/) ? name.to_s : "`#{name}`"
      end
  end
end
