# frozen_string_literal: true

require 'prism'

# The readings of Prism nodes DslExtractor and MacroIndex share.
module PrismHelpers
  private

    # The segments of a constant reference — `Foo::Bar` is ['Foo', 'Bar'] —
    # or none for anything else.
    def constant_path(node)
      case node
      when Prism::ConstantReadNode then [node.name.to_s]
      when Prism::ConstantPathNode then node.parent ? constant_path(node.parent) + [node.name.to_s] : [node.name.to_s]
      else []
      end
    end

    def call_arguments(call)
      call.arguments&.arguments || []
    end

    def literal(node)
      case node
      when Prism::SymbolNode, Prism::StringNode then node.unescaped
      end
    end

    # Whether `node` reads the parameter `parameter` (a Prism parameter node).
    def reads_parameter?(node, parameter)
      parameter.respond_to?(:name) && node.is_a?(Prism::LocalVariableReadNode) && node.name == parameter.name
    end
end
