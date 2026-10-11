# frozen_string_literal: true

require 'prism'
require_relative 'attribute_macros'
require_relative 'prism_helpers'
require_relative 'dsl_extractor/arguments'
require_relative 'dsl_extractor/dispatch'
require_relative 'dsl_extractor/hand_rolled_concerns'
require_relative 'dsl_extractor/iterations'
require_relative 'dsl_extractor/macros'
require_relative 'dsl_extractor/mixins'
require_relative 'dsl_extractor/rendering'

# Extracts the methods the Rails DSL defines, which neither `rbs prototype`
# nor `rigor sig-gen` sees — they are not written with `def`:
#
# - `delegate :a, :b, to: …` (and `delegate(*LIST, to: …)` over a literal list
#   constant of the same scope — ActiveRecord::Querying::QUERYING_METHODS);
# - `class_attribute`, `mattr_*` / `cattr_*`, `config_accessor`, `scope`,
#   `define_method`;
# - the `included do … end` and `class_methods do … end` blocks of a concern:
#   what they define at class level — `def` in `class_methods` included — lands
#   in the concern's ClassMethods module, which Sanitizer then extends onto
#   every class including it, and their `extend X` becomes an `include X` of
#   that module — the same methods, on the same singleton.
#
# With `mixins: true` — for application code, whose RBS `rigor sig-gen`
# writes without any mixin — it also records each class's `include` / `extend`,
# so the concerns a class includes can be followed.
#
# The result is RBS source, nested the way the Ruby source nests its
# modules so names inside resolve the way Ruby resolves them.
class DslExtractor
  include PrismHelpers
  include Arguments
  include Dispatch
  include HandRolledConcerns
  include Iterations
  include Macros
  include Mixins
  include Rendering

  Method = Struct.new(:owner, :singleton, :name, :shape)

  CLASS_LEVEL = %i[included class_methods].freeze

  # `kinds` maps a container path to RBS::AST::Declarations::Class or ::Module:
  # only containers whose kind is known are reopened. The source's own
  # `class` / `module` keywords complete it.
  # `macros` is the index MacroIndex builds from the gems: what calling a gem's
  # macro (`acts_as_taggable_on`) or extending one of its modules
  # (`extend FriendlyId`) does to the calling class.
  def initialize(kinds, mixins: false, macros: {})
    @macros   = macros.fetch('macros', {})
    @hooks    = macros.fetch('extended', {})
    @declared = kinds
    @kinds    = kinds.dup
    @supers   = {}
    @mixins   = mixins
    @methods  = []
    @includes = Hash.new { |hash, key| hash[key] = [] }
    @extends  = Hash.new { |hash, key| hash[key] = [] }
  end

  def extract(files)
    files.each do |file|
      root = Prism.parse_file(file).value
      visit_body(root.statements, [], :body, {})
      on_load_blocks(root)
    end
    self
  end

  def to_rbs
    owners = (@methods.map(&:owner) + @includes.keys + @extends.keys).uniq
    owners = with_superclasses(owners).select { |path| kinds_known?(path) }
    owners.map { |owner| render(owner) }.join("\n")
  end

  private

    # `mode` is :body (a class or module body), :singleton (`class << self`),
    # :included or :class_methods (a concern's blocks: what they define at
    # class level goes to the concern's ClassMethods).
    def visit_body(node, path, mode, constants)
      return if node.nil?
      return visit_body(node.statements, path, mode, constants) if node.is_a?(Prism::BeginNode)

      statements = node.respond_to?(:body) && node.body.is_a?(Array) ? node.body : [node]
      statements.each { |statement| visit(statement, path, mode, constants) }
    end

    def visit(node, path, mode, constants)
      case node
      when Prism::ModuleNode, Prism::ClassNode then visit_container(node, path)
      when Prism::SingletonClassNode then visit_singleton(node, path, constants)
      when Prism::ConstantWriteNode then constants[node.name] = list(node.value)
      when Prism::DefNode then visit_def(node, path, mode)
      when Prism::CallNode then call(node, path, mode, constants)
      when Prism::StatementsNode then visit_body(node, path, mode, constants)
      end
    end

    # `class << self`: what it defines lands on the singleton.
    def visit_singleton(node, path, constants)
      visit_body(node.body, path, :singleton, constants) if node.expression.is_a?(Prism::SelfNode)
    end

    def visit_container(node, path)
      inner = path + constant_path(node.constant_path)
      @kinds[inner] ||= node.is_a?(Prism::ClassNode) ? RBS::AST::Declarations::Class : RBS::AST::Declarations::Module
      record_superclass(inner, node)
      visit_body(node.body, inner, :body, {})
    end

    def visit_def(node, path, mode)
      add(path, mode, true, node.name, :any) if mode == :class_methods && node.receiver.nil?
      hand_rolled_concern(node, path) if mode == :body && node.name == :included && node.receiver.is_a?(Prism::SelfNode)
    end

    # Where a method lands. In a class or module body it is the container's
    # own instance or singleton method; in a concern's `included` or
    # `class_methods` block, a class-level definition goes to ClassMethods.
    def add(path, mode, singleton, name, shape)
      @methods << if CLASS_LEVEL.include?(mode) && singleton
                    Method.new(path + ['ClassMethods'], false, name, shape)
                  else
                    Method.new(path, singleton || mode == :singleton, name, shape)
                  end
    end
end
