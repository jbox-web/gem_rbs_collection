# frozen_string_literal: true

class DslExtractor
  # The Rails and Forwardable macros that define methods by name: `delegate`,
  # `def_delegators`, the attribute macros, `attr_internal`, `scope`,
  # `define_method`, and their `singleton_class.` forms.
  module Macros
    private

      # Rails' `delegate :a, :b, to: :x`, or Forwardable's `delegate [:a, :b] => :x`.
      def delegate(node, path, mode, constants)
        names, options = arguments(node, constants)
        prefix = delegate_prefix(options)
        names.each { |name| add(path, mode, false, :"#{prefix}#{name}", :any) }
        forwarded_keys(node).each { |name| add(path, mode, false, name, :any) }
      end

      def forwarded_keys(node)
        hashes = call_arguments(node).grep(Prism::KeywordHashNode)
        hashes.flat_map(&:elements).grep(Prism::AssocNode).flat_map do |pair|
          pair.key.is_a?(Prism::ArrayNode) ? symbols(pair.key) : [literal(pair.key)&.to_sym].compact
        end
      end

      # Forwardable: `def_delegators :instance, :enable, :enabled?` — the first
      # argument is the accessor, the others the methods (Flipper).
      def forwardable(node, path, mode, _constants)
        names, = arguments(node, {})
        names.drop(1).each { |name| add(path, mode, false, name, :any) }
      end

      # `def_delegator :accessor, :method, :alias` defines the alias, or the method.
      def forwardable_one(node, path, mode, _constants)
        names, = arguments(node, {})
        name = names[2] || names[1]
        add(path, mode, false, name, :any) if name
      end

      def delegate_prefix(options)
        case options[:prefix]
        when Prism::TrueNode then "#{literal(options[:to]).to_s.delete_prefix('@')}_"
        when Prism::SymbolNode, Prism::StringNode then "#{literal(options[:prefix])}_"
        else ''
        end
      end

      # `class_attribute`, `mattr_*` / `cattr_*` and `config_accessor`
      # (ActiveSupport::Configurable), with their `instance_*` options.
      def attribute_macro(node, path, mode, _constants)
        names, = arguments(node, {})
        options = AttributeMacros.options(node)
        names.each do |name|
          AttributeMacros.definitions(node.name, name, options).each do |singleton, method, shape|
            add(path, mode, singleton, method, shape)
          end
        end
      end

      def attr_internal(node, path, mode, _constants)
        names, = arguments(node, {})
        accessors(path, mode, names, node.name.to_s.delete_prefix('attr_internal').delete_prefix('_'))
      end

      # `attr_writer :custom_contexts` in an `included` block (acts-as-taggable-on's
      # Core): `rbs prototype` does not read inside blocks. In a class body it
      # already declares them.
      def block_attribute(node, path, mode, _constants)
        return unless mode == :included

        names, = arguments(node, {})
        accessors(path, mode, names, node.name.to_s.delete_prefix('attr_'))
      end

      # The reader and writer `kind` ('reader', 'writer', or anything else for
      # both) defines for each name, on the instances or on the singleton.
      def accessors(path, mode, names, kind, singleton: false)
        names.each do |name|
          add(path, mode, singleton, name, :reader) unless kind == 'writer'
          add(path, mode, singleton, :"#{name}=", :writer) unless kind == 'reader'
        end
      end

      # `scope :name, -> { … }` defines a class method of the model.
      def scope(node, path, mode, _constants)
        name = literal(call_arguments(node).first)
        add(path, mode, true, name.to_sym, :any) if name
      end

      # `singleton_class.attr_accessor :x` — how ActiveRecord declares its
      # module-level settings (ActiveRecord.action_on_strict_loading_violation) —
      # and `singleton_class.delegate :x, to: :config`
      # (ActionController::RequestForgeryProtection.allow_forgery_protection).
      def singleton_class_receiver?(receiver)
        receiver.is_a?(Prism::CallNode) && receiver.name == :singleton_class &&
          (receiver.receiver.nil? || receiver.receiver.is_a?(Prism::SelfNode))
      end

      def singleton_attribute(node, path, mode)
        names, options = arguments(node, {})
        if node.name == :delegate
          prefix = delegate_prefix(options)
          names.each { |name| add(path, mode, true, :"#{prefix}#{name}", :any) }
        elsif %i[attr_accessor attr_reader attr_writer].include?(node.name)
          accessors(path, mode, names, node.name.to_s.delete_prefix('attr_'), singleton: true)
        end
      end

      def define(node, path, mode, singleton:)
        name = literal(call_arguments(node).first)
        add(path, mode, singleton, name.to_sym, :any) if name
      end

      def define_instance_method(node, path, mode, _constants)
        define(node, path, mode, singleton: false)
      end

      def define_singleton(node, path, mode, _constants)
        define(node, path, mode, singleton: true)
      end
  end
end
