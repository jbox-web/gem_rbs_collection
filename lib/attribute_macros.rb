# frozen_string_literal: true

# The methods ActiveSupport's attribute macros define, as ActiveSupport 8.1.4
# defines them (core_ext/class/attribute.rb, core_ext/module/attribute_accessors.rb,
# configurable.rb) — shared by DslExtractor, which reads them in class bodies,
# and MacroIndex, which reads them in the bodies of a gem's macros.
module AttributeMacros
  CLASS_ATTRIBUTE = %i[class_attribute].freeze
  READERS         = %i[mattr_reader cattr_reader].freeze
  WRITERS         = %i[mattr_writer cattr_writer].freeze
  ACCESSORS       = %i[mattr_accessor cattr_accessor config_accessor].freeze
  MACROS          = (CLASS_ATTRIBUTE + READERS + WRITERS + ACCESSORS).freeze

  # `[singleton?, method name, shape]` for each method `macro` defines for the
  # attribute `name`. `options` maps the `instance_*` options given a literal
  # `true` or `false` to it; the others take their default.
  def self.definitions(macro, name, options = {})
    accessor = options.fetch(:instance_accessor, true)
    reader   = options.fetch(:instance_reader, accessor)
    writer   = options.fetch(:instance_writer, accessor)
    if CLASS_ATTRIBUTE.include?(macro)
      class_attribute(name, reader, writer, options.fetch(:instance_predicate, true))
    else
      module_attribute(macro, name, accessor && reader, accessor && writer)
    end
  end

  # class_attribute's instance predicate needs its instance reader; with
  # `instance_accessor: false`, an explicit `instance_reader: true` still
  # defines the reader.
  def self.class_attribute(name, reader, writer, predicate)
    definitions = [[true, name, :reader], [true, :"#{name}=", :writer]]
    definitions << [true, :"#{name}?", :predicate] if predicate
    definitions << [false, name, :reader] if reader
    definitions << [false, :"#{name}=", :writer] if writer
    definitions << [false, :"#{name}?", :predicate] if predicate && reader
    definitions
  end

  # mattr_* and config_accessor define the instance methods only when both
  # `instance_accessor` and their own `instance_reader` / `instance_writer` hold.
  def self.module_attribute(macro, name, reader, writer)
    defines_reader = !WRITERS.include?(macro)
    defines_writer = !READERS.include?(macro)
    definitions = []
    definitions << [true, name, :reader] if defines_reader
    definitions << [true, :"#{name}=", :writer] if defines_writer
    definitions << [false, name, :reader] if defines_reader && reader
    definitions << [false, :"#{name}=", :writer] if defines_writer && writer
    definitions
  end

  # The `instance_*` options of a macro call given a literal boolean.
  def self.options(call)
    keyword_pairs(call).each_with_object({}) do |pair, options|
      value = boolean(pair.value)
      options[pair.key.unescaped.to_sym] = value if pair.key.is_a?(Prism::SymbolNode) && !value.nil?
    end
  end

  def self.keyword_pairs(call)
    arguments = call.arguments&.arguments || []
    arguments.grep(Prism::KeywordHashNode).flat_map(&:elements).grep(Prism::AssocNode)
  end

  def self.boolean(node)
    case node
    when Prism::TrueNode then true
    when Prism::FalseNode then false
    end
  end
end
