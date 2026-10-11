# frozen_string_literal: true

# The half of MacroEffect that reads what a macro defines under the name its
# first argument gives: methods a `class_eval` string defines, and the
# suffixes `delegate` appends.
module ArgumentEffects
  private

    # A method a `class_eval` string defines from the first argument:
    # `class_eval "def #{relation_name}; …"` in Draper's decorates_association.
    def evaluated_definitions(node, parameter, result)
      return unless parameter.respond_to?(:name)

      name = Regexp.escape(parameter.name.to_s)
      node.slice.scan(/def\s+(self\.)?\#\{#{name}\}([?!=]?)/).each do |singleton, suffix|
        if singleton
          result['singleton_from_argument'] = true if suffix.empty?
        else
          result['instance_suffixes'] |= [suffix]
        end
      end
    end

    # The suffixes `delegate name, "#{name}=", to: :model` appends to the
    # macro's first argument: ["", "="] — action_form's `attribute`.
    def argument_suffixes(call, parameter)
      return [] unless parameter.respond_to?(:name)

      call_arguments(call).filter_map do |argument|
        case argument
        when Prism::LocalVariableReadNode then '' if argument.name == parameter.name
        when Prism::InterpolatedStringNode, Prism::InterpolatedSymbolNode then interpolated_suffix(argument, parameter)
        end
      end
    end

    def interpolated_suffix(node, parameter)
      head, *tail = node.parts
      embedded = head.is_a?(Prism::EmbeddedStatementsNode) && head.statements&.body&.first
      return unless reads_parameter?(embedded, parameter) && tail.all?(Prism::StringNode)

      tail.map(&:unescaped).join
    end
end
