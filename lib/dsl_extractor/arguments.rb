# frozen_string_literal: true

class DslExtractor
  # Reads the names and options a macro call lists, and the literal lists a
  # constant of the same scope is assigned.
  module Arguments
    private

      # The names a macro call lists — literal, or splatted from a literal list
      # constant of the same scope — and its keyword options.
      def arguments(node, constants)
        arguments = call_arguments(node)
        names     = arguments.flat_map { |argument| argument_names(argument, constants) }
        options   = arguments.grep(Prism::KeywordHashNode).flat_map(&:elements).grep(Prism::AssocNode)
        [names, options.to_h { |pair| [literal(pair.key)&.to_sym, pair.value] }]
      end

      def argument_names(argument, constants)
        case argument
        when Prism::SymbolNode, Prism::StringNode then [literal(argument).to_sym]
        when Prism::SplatNode then symbols(constants[constant_path(argument.expression).last&.to_sym])
        else []
        end
      end

      # The symbols of a literal list — `[:a, :b]`, `%i[a b]`, `%w[a b]`, or the
      # keys of a Hash — optionally `.freeze`d.
      def symbols(node)
        node = list(node)
        return [] if node.nil?

        elements = node.is_a?(Prism::HashNode) ? node.elements.grep(Prism::AssocNode).map(&:key) : node.elements
        elements.filter_map { |element| literal(element)&.to_sym }
      end

      # The literal list — Array or Hash — a constant is assigned, `.freeze`d or not.
      def list(node)
        node = node.receiver if node.is_a?(Prism::CallNode) && node.name == :freeze
        node.is_a?(Prism::ArrayNode) || node.is_a?(Prism::HashNode) ? node : nil
      end
  end
end
