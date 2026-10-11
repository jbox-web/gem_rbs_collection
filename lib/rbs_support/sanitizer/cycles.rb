# frozen_string_literal: true

module RbsSupport
  class Sanitizer
    # The include that would make a module its own ancestor, which RBS rejects
    # (RBS::RecursiveAncestorError) along with every class including either side.
    # A hand-rolled hook including a module back into its base
    # (`base.class_eval { include Representable::JSON }` in JSON::Hash) reads as
    # an include of the concern itself; and a name the source reaches before the
    # file that defines it loads resolves, statically, to a module that is not
    # yet there (`include Hash` in JSON). The first include closing a cycle is
    # dropped; the cycle broken, the others are kept.
    module Cycles
      INSTANCE_MIXINS = [RBS::AST::Members::Include, RBS::AST::Members::Prepend].freeze
      private_constant :INSTANCE_MIXINS

      private

        def cyclic?(path, member, name)
          return false unless INSTANCE_MIXINS.include?(member.class)

          owner = RBS::TypeName.parse("::#{path.join('::')}")
          return false unless reaches?(name, owner, Set.new)

          @dropped_mixins << [owner, name]
          true
        end

        def reaches?(from, target, seen)
          return true if from == target
          return false unless seen.add?(from)

          included_names(from).any? do |name|
            !@dropped_mixins.include?([from, name]) && reaches?(name, target, seen)
          end
        end

        def included_names(name)
          @included_names[name] ||= begin
            entry = @env.class_decls[name]
            members = entry ? entry.each_decl.flat_map(&:members) : []
            members.filter_map { |member| member.name if INSTANCE_MIXINS.include?(member.class) }
          end
        end
    end
  end
end
