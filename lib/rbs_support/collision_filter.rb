# frozen_string_literal: true

module RbsSupport
  # The declarations Environment#insert_rbs_decl would accept, given what the
  # environment and the declarations filtered so far declare — and the names
  # dropped: a constant declared twice, a constant where a class is declared,
  # a module where a class is.
  #
  # Only the colliding declaration goes: Environment#add_source inserts a whole
  # top-level declaration or raises, and dropping it would take with it every
  # class it nests (`module ::ActiveRecord`, 1,935 lines of activerecord's RBS).
  class CollisionFilter
    attr_reader :rejected

    def initialize(env)
      @env      = env
      @added    = {}
      @rejected = []
    end

    # `declarations` minus those that collide, under `namespace` (an RBS::Namespace).
    def call(declarations, namespace = RBS::Namespace.root)
      declarations.filter_map do |declaration|
        name = RbsSupport.declaration_name(declaration, namespace)
        next declaration if name.nil?
        next if rejected?(name, kind(declaration))

        RbsSupport.container?(declaration) ? without_member_collisions(declaration, name) : declaration
      end
    end

    private

      # Records `name` as added, or as rejected when it collides.
      def rejected?(name, kind)
        if collides?(name, kind)
          @rejected << name.to_s
          return true
        end

        @added[name] = kind
        false
      end

      def without_member_collisions(declaration, name)
        members = declaration.members.flat_map do |member|
          member.is_a?(RBS::AST::Declarations::Base) ? call([member], name.to_namespace) : [member]
        end
        declaration.update(members: members)
      end

      def kind(declaration)
        case declaration
        when RBS::AST::Declarations::Class then :class
        when RBS::AST::Declarations::Module then :module
        when RBS::AST::Declarations::Interface then :interface
        when RBS::AST::Declarations::TypeAlias then :type_alias
        else :constant
        end
      end

      # The rules of Environment#insert_rbs_decl: a class or module reopens one of
      # the same kind and collides with anything else; an interface or a type alias
      # is declared once; a constant or an alias collides with any constant name.
      def collides?(name, kind)
        existing = @added[name] || existing_kind(name, kind)
        return false if existing.nil?

        %i[class module].include?(kind) ? existing != kind : true
      end

      def existing_kind(name, kind)
        case kind
        when :interface then (:interface if @env.interface_decls.key?(name))
        when :type_alias then (:type_alias if @env.type_alias_decls.key?(name))
        else constant_kind(@env.constant_entry(name))
        end
      end

      def constant_kind(entry)
        case entry
        when RBS::Environment::ClassEntry then :class
        when RBS::Environment::ModuleEntry then :module
        when nil then nil
        else :constant
        end
      end
  end
end
