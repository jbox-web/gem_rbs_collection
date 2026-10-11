# frozen_string_literal: true

class DslExtractor
  # A literal list iterated to generate one method per element, or to
  # include one module per element:
  #
  #   LOGGER_METHODS.each do |method|        MODULES.each do |mod|
  #     class_eval <<-RUBY                     include mod
  #       def #{method}(...)                 end
  #
  # The block's source is searched for `def #{var}` / `def self.#{var}`,
  # `define_method(:"#{var}")` and `scope var.to_sym` / `scope :"#{var}"`,
  # with a `?`, `!` or `=` suffix and a `.downcase` / `.underscore` applied to
  # the element, and for `include var` (ActionController::Base and ::API
  # include their modules so). The list is an Array, or a Hash whose keys are
  # iterated (Locale::SUPPORTED.each_key).
  module Iterations
    # The iterations whose first block parameter is an element — or a key — of
    # the receiver.
    ITERATIONS = %i[each each_key each_with_index].freeze

    # The String transformations an interpolated method name may apply to the
    # iterated element (`def #{locale.downcase}` in Locale).
    TRANSFORMS = {
      'downcase'   => :downcase.to_proc,
      'underscore' => ->(name) { name.gsub(/([a-z\d])([A-Z])/, '\1_\2').tr('-', '_').downcase },
      'to_s'       => ->(name) { name },
      'to_sym'     => ->(name) { name },
    }.freeze

    CHAIN = "((?:\\.(?:#{TRANSFORMS.keys.join('|')}))*)".freeze

    private

      def iterated_definitions(node, path, mode, constants)
        return unless node.block.is_a?(Prism::BlockNode)

        items    = iterated_list(node.receiver, constants)
        variable = block_variable(node.block)
        iterate(node.block.slice, items, variable, path, mode) if items && variable
      end

      def iterate(source, items, variable, path, mode)
        var = Regexp.escape(variable.name.to_s)
        iterated_methods(source, var, symbols(items).map(&:to_s), path, mode)
        iterated_includes(source, var, items, path)
      end

      # The block's first required parameter: `|method|` in `LIST.each do |method|`.
      def block_variable(block)
        parameters = block.parameters
        return unless parameters.is_a?(Prism::BlockParametersNode) && parameters.parameters

        variable = parameters.parameters.requireds.first
        variable if variable.respond_to?(:name)
      end

      def iterated_list(receiver, constants)
        case receiver
        when Prism::ArrayNode, Prism::HashNode then receiver
        when Prism::ConstantReadNode then constants[receiver.name]
        when Prism::CallNode then receiver.name == :keys ? iterated_list(receiver.receiver, constants) : nil
        end
      end

      def iterated_methods(source, var, names, path, mode)
        interpolation = /\#\{#{var}#{CHAIN}\}/
        iterated_defs(source, interpolation, names, path, mode)
        iterated_scopes(source, var, names, path, mode)
      end

      def iterated_defs(source, interpolation, names, path, mode)
        source.scan(/def (self\.)?([a-z_]*)#{interpolation}([a-z_?!=]*)/).each do |singleton, before, chain, after|
          each_name(names, chain) { |name| add(path, mode, !singleton.nil?, :"#{before}#{name}#{after}", :any) }
        end
        source.scan(/define_method\(?\s*:?"([a-z_]*)#{interpolation}([a-z_?!=]*)"/).each do |before, chain, after|
          each_name(names, chain) { |name| add(path, mode, false, :"#{before}#{name}#{after}", :any) }
        end
      end

      def iterated_scopes(source, var, names, path, mode)
        source.scan(/scope\(?\s*#{var}#{CHAIN}\s*,/).each do |(chain)|
          each_name(names, chain) { |name| add(path, mode, true, name.to_sym, :any) }
        end
        source.scan(/scope\(?\s*:"([a-z_]*)\#\{#{var}#{CHAIN}\}([a-z_?!]*)"/).each do |before, chain, after|
          each_name(names, chain) { |name| add(path, mode, true, :"#{before}#{name}#{after}", :any) }
        end
      end

      def each_name(names, chain, &)
        transforms = chain.to_s.split('.').reject(&:empty?).map { |transform| TRANSFORMS.fetch(transform) }
        names.map { |name| transforms.reduce(name) { |value, transform| transform.call(value) } }.each(&)
      end

      def iterated_includes(source, var, items, path)
        return unless items.is_a?(Prism::ArrayNode) && source.match?(/\binclude\(?\s*#{var}\b/)

        items.elements.each do |element|
          name = constant_path(element)
          @includes[path] << name.join('::') unless name.empty?
        end
      end
  end
end
