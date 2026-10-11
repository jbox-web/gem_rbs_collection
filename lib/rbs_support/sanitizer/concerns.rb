# frozen_string_literal: true

module RbsSupport
  class Sanitizer
    # The ActiveSupport::Concern half of Sanitizer: a class including a concern
    # also extends the concern's ClassMethods, and those of the concerns it
    # includes in turn — what ActiveSupport::Concern#append_features does at
    # runtime. Needs `@env`, and `@concerns` / `@extended` set up by the includer.
    module Concerns
      CONCERN = RBS::TypeName.parse('::ActiveSupport::Concern')

      private

        # Every concern of the environment, mapped to the ClassMethods modules its
        # inclusion extends: its own, then — transitively — those of the concerns
        # it includes.
        def concerns
          direct = @env.class_decls.each_with_object({}) do |(name, entry), found|
            mixins = entry.each_decl.flat_map(&:members)
            found[name] = concern_entry(name, mixins) if concern?(mixins)
          end
          direct.to_h { |name, _| [name, class_methods_closure(name, direct, Set.new)] }
        end

        def concern?(mixins)
          mixins.any? { |mixin| mixin.is_a?(RBS::AST::Members::Extend) && mixin.name == CONCERN }
        end

        # The concerns it includes, and its own ClassMethods module.
        def concern_entry(name, mixins)
          [mixins.grep(RBS::AST::Members::Include).map(&:name), RBS::TypeName.parse("#{name}::ClassMethods")]
        end

        def class_methods_closure(name, direct, visited)
          return [] if visited.include?(name) || !direct.key?(name)

          visited << name
          included, own = direct.fetch(name)
          modules = @env.module_decl?(own) ? [own] : []
          modules + included.flat_map { |other| class_methods_closure(other, direct, visited) }
        end

        # The `extend` members a class or module gains from the concerns it
        # includes — once per class, whichever reopening includes them.
        def concern_extensions(path, members)
          name = RBS::TypeName.parse("::#{path.join('::')}")
          return [] if @concerns.key?(name)

          modules = members.grep(RBS::AST::Members::Include).flat_map { |m| @concerns.fetch(m.name, []) }
          modules.uniq.reject { |mod| @extended.include?([path, mod]) }.map do |mod|
            @extended << [path, mod]
            RBS::AST::Members::Extend.new(name: mod, args: [], annotations: [], location: nil, comment: nil)
          end
        end
    end
  end
end
