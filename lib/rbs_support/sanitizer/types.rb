# frozen_string_literal: true

module RbsSupport
  class Sanitizer
    # The type half of Sanitizer: degrades to `untyped` the type names that resolve
    # nowhere in `@env`, completes the arguments of a generic used bare, and
    # widens the empty literals `rigor sig-gen` types a return after.
    module Types
      private

        # `class SchemaDumper < SchemaDumper`, written in ConnectionAdapters: Ruby
        # resolves the superclass before the class exists, so it reaches
        # ActiveRecord::SchemaDumper, while RBS resolves it to the class itself
        # (RBS::RecursiveAncestorError). A superclass naming its own class is looked
        # up again in the enclosing namespaces.
        def sanitize_super_class(super_class, path)
          name = known(super_class.name)
          name = enclosing(path) if name && segments(name) == path
          name && RBS::AST::Declarations::Class::Super.new(
            name: name, args: arity(name, super_class.args.map { |arg| sanitize_type(arg) }), location: nil
          )
        end

        def segments(name)
          name.to_s.delete_prefix('::').split('::')
        end

        def enclosing(path)
          (path.size - 2).downto(0).each do |depth|
            candidate = RBS::TypeName.parse("::#{(path.first(depth) + [path.last]).join('::')}")
            return candidate if @env.type_name?(candidate)
          end
          nil
        end

        # MethodType#map_type maps the function's types and the block's, not the
        # types nested inside them: sanitize_type recurses on its own.
        def sanitize_method_type(method_type)
          mapped = method_type.map_type { |type| sanitize_type(type) }
          mapped.update(type: mapped.type.with_return_type(widen_empty(mapped.type.return_type)))
        end

        # `rigor sig-gen` types a return after the literal a method starts from —
        # `def clear!; store = {}; …` becomes `-> {}`, the record with no key, and
        # reading any key of it reads nil. Never the intended type: widened.
        def widen_empty(type)
          case type
          when RBS::Types::Record, RBS::Types::Tuple then widen_literal(type)
          when RBS::Types::Union then RBS::Types::Union.new(types: type.types.map { |t| widen_empty(t) }, location: nil)
          when RBS::Types::Optional then RBS::Types::Optional.new(type: widen_empty(type.type), location: nil)
          else type
          end
        end

        def widen_literal(type)
          if type.is_a?(RBS::Types::Record)
            type.fields.empty? ? hash_type : type
          else
            type.types.empty? ? array_type : type
          end
        end

        def hash_type
          RBS::Types::ClassInstance.new(name: RBS::TypeName.parse('::Hash'), args: [UNTYPED, UNTYPED], location: nil)
        end

        def array_type
          RBS::Types::ClassInstance.new(name: RBS::TypeName.parse('::Array'), args: [UNTYPED], location: nil)
        end

        def sanitize_type(type)
          case type
          when RBS::Types::ClassInstance, RBS::Types::Interface, RBS::Types::Alias then sanitize_named_type(type)
          when RBS::Types::ClassSingleton then known(type.name) ? type : UNTYPED
          else type.respond_to?(:map_type) ? type.map_type { |inner| sanitize_type(inner) } : type
          end
        end

        def sanitize_named_type(type)
          name = known(type.name)
          return UNTYPED if name.nil?

          args = type.args.map { |arg| sanitize_type(arg) }
          args = arity(name, args) if type.is_a?(RBS::Types::ClassInstance)
          type.class.new(name: name, args: args, location: nil)
        end

        def known(name)
          return name if name.absolute? && @env.type_name?(name)

          nil
        end

        def arity(name, args)
          expected = type_params(name)
          return args if expected.nil? || args.size == expected

          args.empty? ? Array.new(expected) { UNTYPED } : args
        end

        # Two sources may declare one class with different parameters
        # (FFI::Struct: ffi's own `sig/` and another source): RBS then refuses
        # the entry's parameters, and the first declaration's are taken.
        def type_params(name)
          entry = @env.class_decls[@env.normalize_type_name(name)]
          entry&.type_params&.size
        rescue RBS::GenericParameterMismatchError
          entry.each_decl.first&.type_params&.size
        end
    end
  end
end
