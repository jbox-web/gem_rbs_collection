# frozen_string_literal: true

class DslExtractor
  # The concerns written by hand, with `def self.included(base)`.
  module HandRolledConcerns
    private

      # The concern written by hand, without ActiveSupport::Concern:
      #
      #   def self.included(base)
      #     base.include(Phlex::Rails::Helpers::Translate)
      #     base.extend(ClassMethods)
      #   end
      #
      # It is marked as a concern, so Sanitizer extends its ClassMethods onto the
      # including classes, as for ActiveSupport::Concern; `base.extend(Other)`
      # becomes an `include Other` of ClassMethods, `base.include(Other)` an
      # `include Other` of the module (Widget::Translation).
      #
      # The same calls written without a receiver inside `base.class_eval do … end`
      # (or `class_exec`) count too: representable's hook extends ForCollection
      # that way, which brings `for_collection` to every Decorator.
      def hand_rolled_concern(node, path)
        base  = node.parameters&.requireds&.first
        calls = MIXIN_CALLS.scan(node).select { |call| reads_parameter?(call.receiver, base) }
        calls += class_eval_mixins(node, base)
        return if calls.empty?

        @extends[path] << 'ActiveSupport::Concern'
        calls.each { |call| hand_rolled_mixins(call, path) }
      end

      MIXIN_CALLS = Prism::Pattern.new('CallNode[name: :extend | :include]')
      private_constant :MIXIN_CALLS

      def class_eval_mixins(node, base)
        evals = Prism::Pattern.new('CallNode[name: :class_eval | :class_exec]').scan(node).select do |call|
          reads_parameter?(call.receiver, base) && call.block.is_a?(Prism::BlockNode)
        end
        evals.flat_map { |call| MIXIN_CALLS.scan(call.block).select { |mixin| mixin.receiver.nil? } }
      end

      def hand_rolled_mixins(call, path)
        owner = call.name == :extend ? path + ['ClassMethods'] : path
        call_arguments(call).each do |argument|
          name = constant_path(argument)
          @includes[owner] << name.join('::') unless name.empty? || own_class_methods?(name, path)
        end
      end

      # `ClassMethods`, or the concern's own ClassMethods written qualified
      # (`base.extend ActsAsTaggableOn::Taggable::Related::ClassMethods`): it is
      # the module Sanitizer extends, not one to include into itself — that
      # would make it its own ancestor (RBS::RecursiveAncestorError).
      def own_class_methods?(name, path)
        name.last == 'ClassMethods' && (name.size == 1 || path.last(name.size - 1) == name[0...-1])
      end
  end
end
