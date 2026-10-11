# frozen_string_literal: true

require_relative 'argument_effects'
require_relative 'attribute_macros'
require_relative 'prism_helpers'

# What a gem method's body does to the class calling it — for MacroIndex:
# the modules it includes or extends, the methods it defines, and, `depth`
# calls deep, what the methods of its own namespace it calls do.
class MacroEffect
  include ArgumentEffects
  include PrismHelpers

  LISTS = ['include', 'extend', 'singleton_methods', 'instance_methods', 'instance_suffixes'].freeze
  FLAGS = ['singleton_from_argument', 'instance_from_argument', 'accessors_from_arguments'].freeze

  ACCESSORS = { attr_accessor: 'accessor', attr_reader: 'reader', attr_writer: 'writer' }.freeze

  def self.blank
    LISTS.to_h { |key| [key, []] }.merge(FLAGS.to_h { |key| [key, false] })
  end

  # The union of two effects of one macro name, defined by two modules or gems.
  def self.merge(into, effect)
    LISTS.each { |key| into[key] = (into.fetch(key, []) + effect.fetch(key, [])).uniq }
    FLAGS.each { |key| into[key] ||= effect[key] }
    into
  end

  # `methods`: the definitions MacroIndex collected, by namespace; `known`: the
  # paths of the classes and modules the RBS declare.
  def initialize(methods, known)
    @methods = methods
    @known   = known
  end

  def call(definition, depth)
    result = self.class.blank
    first  = definition.node.parameters&.requireds&.first
    evaluated_definitions(definition.node, first, result)
    calls(definition.node).each { |call| apply(call, definition, first, depth, result) }
    result
  end

  private

    def apply(invocation, definition, first, depth, result)
      case invocation.name
      when :include, :extend then add_mixins(invocation, definition, result)
      when :define_singleton_method, :define_method then definition_flag(invocation, first, result)
      when *AttributeMacros::MACROS, *ACCESSORS.keys then attribute_methods(invocation, result)
      when :delegate then result['instance_suffixes'] |= argument_suffixes(invocation, first)
      else followed(definition, invocation, depth).each { |other| self.class.merge(result, call(other, depth - 1)) }
      end
    end

    def add_mixins(invocation, definition, result)
      names = call_arguments(invocation).filter_map do |argument|
        resolve(definition.namespace, constant_path(argument))
      end
      result[invocation.name.to_s] = (result[invocation.name.to_s] + names).uniq
    end

    def definition_flag(call, first, result)
      key = call.name == :define_method ? 'instance_from_argument' : 'singleton_from_argument'
      result[key] ||= reads_parameter?(call_arguments(call).first, first)
    end

    def attribute_methods(call, result)
      if AttributeMacros::MACROS.include?(call.name)
        attribute_macro_methods(call, result)
      elsif call_arguments(call).any?(Prism::LocalVariableReadNode)
        result['accessors_from_arguments'] ||= ACCESSORS.fetch(call.name)
      end
    end

    def attribute_macro_methods(call, result)
      options = AttributeMacros.options(call)
      call_arguments(call).filter_map { |argument| literal(argument) }.each do |name|
        AttributeMacros.definitions(call.name, name, options).each do |singleton, method, _|
          result[singleton ? 'singleton_methods' : 'instance_methods'] |= [method.to_s]
        end
      end
    end

    # The calls of a method body — with no receiver, or `self`, or the
    # parameter a `self.extended(base)` hook receives (`base.extend(Base)`).
    def calls(node)
      base = node.parameters&.requireds&.first
      Prism::Pattern.new('CallNode').scan(node).select do |call|
        call.receiver.nil? || call.receiver.is_a?(Prism::SelfNode) || reads_parameter?(call.receiver, base)
      end
    end

    def followed(definition, call, depth)
      return [] if depth.zero? || call.receiver

      @methods[definition.namespace].select { |other| other.node.name == call.name && other != definition }
    end

    # Resolves a constant the way Ruby does, from the namespace outwards,
    # against the classes and modules the RBS declare.
    def resolve(namespace, segments)
      return if segments.empty?

      namespace.size.downto(0).each do |depth|
        candidate = namespace.first(depth) + segments
        return "::#{candidate.join('::')}" if @known.include?(candidate)
      end
      nil
    end
end
