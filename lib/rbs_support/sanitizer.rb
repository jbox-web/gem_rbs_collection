# frozen_string_literal: true

require_relative 'sanitizer/concerns'
require_relative 'sanitizer/cycles'
require_relative 'sanitizer/types'

module RbsSupport
  # Makes the generated RBS build, by degrading what cannot resolve rather than
  # letting RBS reject a whole class — rigor then reads the class as Dynamic[top],
  # real methods and typos alike:
  #
  # - a type name that resolves nowhere becomes `untyped` (in a method type), or
  #   is dropped (as a superclass or a mixin) — `rbs prototype` writes the names
  #   as the source spells them, and the source reaches some through a constant
  #   alias (ActiveRecord::Type::Value = ActiveModel::Type::Value) or a gem the
  #   collection has no RBS for;
  # - a generic class or module used without type arguments gets `untyped` ones
  #   (`include Enumerable`, `class ArrayInquirer < Array`);
  # - an alias of a method nothing declares becomes a method of its own — the
  #   original is often defined by `delegate`, which no generator sees
  #   (`alias include? has_key?` in ActionController::Parameters);
  # - a method declared twice on a class, across reopenings, keeps its first
  #   declaration;
  # - a class including an ActiveSupport::Concern also extends the concern's
  #   ClassMethods, and those of the concerns it includes in turn — what
  #   ActiveSupport::Concern#append_features does at runtime. Without it,
  #   ActiveRecord::Base has none of the class methods its concerns bring
  #   (create!, transaction, human_attribute_name…).
  class Sanitizer
    include Concerns
    include Cycles
    include Types

    # `drop_unanchored`: a class whose superclass resolves nowhere is dropped
    # rather than written without it. For a gem, the class is better declared an
    # Object than missing; for an application's own RBS it is the reverse — rigor
    # reads the superclass in the source as long as no RBS says otherwise
    # (Admin::Icon < UiKit::Icon, from a gem without RBS, would lose all of
    # Phlex), which is also what `rigor sig-gen` does.
    def initialize(env, deferred, drop_unanchored: false)
      @drop_unanchored = drop_unanchored
      @env      = env
      @deferred = deferred
      @declared = Set.new(deferred.method_keys)
      @kept     = Set.new
      @extended = Set.new
      @concerns = concerns
      @dropped_mixins = Set.new
      @included_names = {}
    end

    def call(declarations)
      collect_declared(declarations, [])
      declarations.filter_map { |declaration| sanitized(declaration, []) }
    end

    private

      def collect_declared(declarations, namespace)
        declarations.each do |declaration|
          next unless RbsSupport.container?(declaration)

          path = RbsSupport.qualified(namespace, declaration.name)
          declaration.members.each { |member| @declared.merge(readable_method_keys(member, path)) }
          collect_declared(declaration.members, path)
        end
      end

      # The keys of the methods a `def`, `attr_reader` or `attr_accessor` defines
      # under its own name — what an `alias` can point to.
      def readable_method_keys(member, path)
        case member
        when RBS::AST::Members::MethodDefinition then [[path, member.singleton?, member.name]]
        when RBS::AST::Members::AttrReader, RBS::AST::Members::AttrAccessor then [RbsSupport.method_key(path, member)]
        else []
        end
      end

      def sanitize_declaration(declaration, namespace)
        path    = RbsSupport.qualified(namespace, declaration.name)
        members = declaration.members.filter_map { |member| sanitized(member, path) }
        members += concern_extensions(path, members)
        updated = declaration.update(members: members)
        return updated unless declaration.is_a?(RBS::AST::Declarations::Class) && declaration.super_class

        super_class = sanitize_super_class(declaration.super_class, path)
        return if super_class.nil? && @drop_unanchored

        updated.update(super_class: super_class)
      end

      # The member sanitized, or nil when an earlier member already defines its method.
      def sanitized(member, path)
        sanitize_member(member, path) unless duplicate?(member, path)
      end

      def sanitize_member(member, path)
        case member
        when *CONTAINERS then sanitize_declaration(member, path)
        when RBS::AST::Members::MethodDefinition then sanitize_method(member)
        when RBS::AST::Members::Alias then sanitize_alias(member, path)
        when *MIXINS then sanitize_mixin(member, path)
        when *ATTRIBUTES then member.update(type: sanitize_type(member.type))
        when RBS::AST::Declarations::Constant then sanitize_constant(member)
        else member
        end
      end

      def sanitize_method(member)
        overloads = member.overloads.map do |overload|
          overload.update(method_type: sanitize_method_type(overload.method_type))
        end
        member.update(overloads: overloads)
      end

      def sanitize_alias(member, path)
        orphan = !@declared.include?(RbsSupport.method_key(path, member, member.old_name))
        orphan ? untyped_method(member.new_name, member.kind == :singleton) : member
      end

      def sanitize_mixin(member, path)
        name = known(member.name)
        return if name.nil? || cyclic?(path, member, name)

        member.class.new(
          name: name, args: arity(name, member.args.map { |arg| sanitize_type(arg) }),
          annotations: member.annotations, location: nil, comment: member.comment
        )
      end

      def sanitize_constant(member)
        RBS::AST::Declarations::Constant.new(
          name: member.name, type: sanitize_type(member.type), location: nil, comment: member.comment,
          annotations: member.annotations
        )
      end

      # Whether a `def`, `alias` or `attr_*` defines a method an earlier member
      # of the class — in any reopening — already defines (WeakSet#to_a: a `def`
      # and an `alias`). The first one is kept.
      def duplicate?(member, path)
        keys = RbsSupport.defined_method_keys(member, path)
        keys = [RbsSupport.method_key(path, member, member.new_name)] if member.is_a?(RBS::AST::Members::Alias)
        return false if keys.empty?
        return true if keys.any? { |key| @kept.include?(key) }

        @kept.merge(keys)
        false
      end

      def untyped_method(name, singleton)
        source = "class Placeholder\n  def #{'self.' if singleton}#{name}: " \
                 "(*untyped, **untyped) ?{ (*untyped) -> untyped } -> untyped\nend\n"
        RbsSupport.parse(source).first.members.first
      end
  end
end
