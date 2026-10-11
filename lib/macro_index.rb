# frozen_string_literal: true

require 'prism'
require_relative 'macro_effect'

# Indexes what a gem's macros do to the class that calls them, so the code
# calling them can be typed — the gem's RBS cannot say it: `acts_as_taggable_on`
# is a method of a module the gem extends onto ActiveRecord::Base, and only its
# body shows that it includes ActsAsTaggableOn::Taggable::Core and four more.
#
# For each method of the gem, the index records:
#
# - the modules its body includes or extends (`include Core`, `extend
#   ClassMethods`), following the calls it makes to the other methods of its
#   own module (`acts_as_taggable_on` → `taggable_on`);
# - whether it defines a method named by its first argument
#   (`define_singleton_method(name)` in `pg_search_scope`);
# - the methods its class attributes define (`class_attribute
#   :_ransack_aliases`, `cattr_accessor :xlsx_columns`), on the class and on
#   its instances;
# - whether it defines an accessor per argument (`attr_accessor attribute`
#   over the arguments of action_form's `virtual_attributes`).
#
# And for each module defining `self.extended(base)`, what extending it does
# (`extend FriendlyId` extends FriendlyId::Base and includes FriendlyId::Model).
#
# Only methods that do one of those are recorded, under their name; the
# constant names are made absolute against `known`, the paths of the classes
# and modules the generated RBS declare, the way Ruby resolves them — from the
# method's own namespace outwards.
class MacroIndex
  include PrismHelpers

  # Hooks and Ruby callbacks: called by Ruby, never as macros.
  SKIPPED = %i[
    included extended inherited prepended append_features prepend_features method_added
  ].freeze

  # Follows the calls a macro makes to the methods of its own module this deep.
  DEPTH = 2

  # `macro`: whether a class body can call the method without a receiver.
  Definition = Struct.new(:namespace, :node, :macro)

  # The union of two effects of one macro name, defined by two modules or gems.
  def self.merge(into, effect)
    MacroEffect.merge(into, effect)
  end

  def initialize(known)
    @known   = known
    @methods = Hash.new { |hash, key| hash[key] = [] }
    @hooks   = []
  end

  def index(files)
    files.each { |file| collect(Prism.parse_file(file).value.statements, []) }
    effects = MacroEffect.new(@methods, @known)
    { 'macros' => macros(effects), 'extended' => extended(effects) }
  end

  private

    # `kind` is :module or :class — the top level counts as a module: its
    # methods land on Object, callable from any class body. `singleton` is
    # whether a `def` here defines a singleton method (`class << self`).
    def collect(node, namespace, kind = :module, singleton: false)
      return if node.nil?

      children = node.is_a?(Prism::StatementsNode) ? node.body : [node]
      children.each { |child| collect_child(child, namespace, kind, singleton) }
    end

    def collect_child(child, namespace, kind, singleton)
      case child
      when Prism::ModuleNode, Prism::ClassNode
        inner = child.is_a?(Prism::ClassNode) ? :class : :module
        collect(child.body, namespace + constant_path(child.constant_path), inner)
      when Prism::SingletonClassNode, Prism::BeginNode then collect_nested(child, namespace, kind, singleton)
      when Prism::DefNode
        record(child, namespace, kind, singleton || child.receiver.is_a?(Prism::SelfNode))
      end
    end

    # `class << self` defines singleton methods; a `begin` block keeps the scope.
    def collect_nested(child, namespace, kind, singleton)
      if child.is_a?(Prism::BeginNode)
        collect(child.statements, namespace, kind, singleton: singleton)
      elsif child.expression.is_a?(Prism::SelfNode)
        collect(child.body, namespace, kind, singleton: true)
      end
    end

    # A macro is a method a class body calls without a receiver: an instance
    # method of a module, which reaches the class by `extend`, or a class
    # method of a class, inherited by its subclasses. A module's own singleton
    # methods are not — `FriendlyId::Finders.setup(model_class)` is a plugin
    # hook, and indexing it as a macro would apply its effect to every class
    # body calling a `setup` of its own (ActionView::TestCase's
    # `setup :setup_with_controller`). Neither are a class's instance methods.
    # All of them are kept, to follow the calls a macro makes.
    def record(node, namespace, kind, singleton)
      if singleton && node.name == :extended
        @hooks << Definition.new(namespace, node, false)
      elsif !SKIPPED.include?(node.name)
        macro = kind == :module ? !singleton : singleton
        @methods[namespace] << Definition.new(namespace, node, macro)
      end
    end

    def macros(effects)
      @methods.values.flatten.select(&:macro).each_with_object({}) do |definition, index|
        effect = effects.call(definition, DEPTH)
        next if effect.values.all? { |value| [[], false].include?(value) }

        MacroEffect.merge(index[definition.node.name.to_s] ||= MacroEffect.blank, effect)
      end
    end

    def extended(effects)
      @hooks.to_h do |definition|
        ["::#{definition.namespace.join('::')}", effects.call(definition, DEPTH)]
      end
    end
end
