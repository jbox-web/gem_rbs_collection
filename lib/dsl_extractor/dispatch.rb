# frozen_string_literal: true

class DslExtractor
  # Sends each call a class body makes to the method handling its macro.
  module Dispatch
    # The method handling each macro a class body calls without a receiver; any
    # other is looked up in the gem macros.
    HANDLERS = {
      included:                :class_level_block,
      class_methods:           :class_level_block,
      delegate:                :delegate,
      def_delegators:          :forwardable,
      def_instance_delegators: :forwardable,
      def_delegator:           :forwardable_one,
      def_instance_delegator:  :forwardable_one,
      scope:                   :scope,
      attr_accessor:           :block_attribute,
      attr_reader:             :block_attribute,
      attr_writer:             :block_attribute,
      define_method:           :define_instance_method,
      define_singleton_method: :define_singleton,
      extend:                  :mixin_call,
      include:                 :mixin_call,
    }.merge(
      AttributeMacros::MACROS.to_h { |name| [name, :attribute_macro] },
      # `attr_internal` (ActiveSupport's Module extension) defines instance
      # accessors over an `@_name` ivar — ActionController::Metal#request.
      %i[attr_internal attr_internal_accessor attr_internal_reader attr_internal_writer].to_h do |name|
        [name, :attr_internal]
      end
    ).freeze

    private

      def call(node, path, mode, constants)
        return if path.empty?
        return singleton_attribute(node, path, mode) if singleton_class_receiver?(node.receiver)
        return iterated_definitions(node, path, mode, constants) if Iterations::ITERATIONS.include?(node.name)
        return if node.receiver && !node.receiver.is_a?(Prism::SelfNode)

        __send__(HANDLERS.fetch(node.name, :gem_macro), node, path, mode, constants)
      end

      def class_level_block(node, path, _mode, constants)
        visit_body(node.block&.body, path, node.name, constants) if node.block.is_a?(Prism::BlockNode)
      end
  end
end
