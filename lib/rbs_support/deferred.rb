# frozen_string_literal: true

module RbsSupport
  # What the RBS given to `--defer-to` already declares: method keys
  # `[path, singleton?, name]` (from `def` and `attr_*` alike), the type
  # parameters of each class or module, and the classes declared with a
  # superclass — and the generated declarations giving way to it.
  class Deferred
    attr_reader :method_keys, :type_params, :super_classes

    # `paths` are directories, searched for `.rbs` files, or files.
    def self.load(paths)
      new.tap do |deferred|
        RbsSupport.rbs_files(paths).each do |file|
          deferred.index(RbsSupport.parse(File.read(file, encoding: 'UTF-8')))
        end
      end
    end

    def initialize
      @method_keys   = Set.new
      @type_params   = {}
      @super_classes = Set.new
    end

    def index(declarations, namespace = [])
      declarations.each do |declaration|
        next unless RbsSupport.container?(declaration)

        path = RbsSupport.qualified(namespace, declaration.name)
        index_shape(declaration, path)
        declaration.members.each { |member| @method_keys.merge(RbsSupport.defined_method_keys(member, path)) }
        index(declaration.members, path)
      end
      self
    end

    # Gives way to the deferred RBS (rigor's plugin signatures):
    #
    # - a method they declare is dropped here — RBS rejects two definitions of one
    #   method (RBS::DuplicatedMethodDefinitionError on ::Arel.sql), and theirs are
    #   the better typed;
    # - a class they declare generic takes their type parameters — RBS rejects two
    #   declarations of one class with different parameters, and rigor then stands
    #   its plugin down (rigor-activerecord's ActiveRecord::Relation[Model]);
    # - a class they declare with a superclass loses its own — RBS rejects two
    #   different superclasses (rigor-activerecord still has StatementInvalid <
    #   ActiveRecordError, Rails 8.1 made it an AdapterError), and a reopening
    #   without one merges with theirs.
    #
    # Instance, class-instance and class variables are dropped as well: they are
    # Rails internals, and a module declaring one its extender also declares fails
    # to build (RBS::InstanceVariableDuplicationError on ActiveModel::Naming#@_model_name).
    def give_way(declarations, namespace = [])
      declarations.map do |declaration|
        next declaration unless RbsSupport.container?(declaration)

        path    = RbsSupport.qualified(namespace, declaration.name)
        params  = @type_params.fetch(path, declaration.type_params)
        updated = declaration.update(members: given_way_members(declaration, path), type_params: params)
        next updated unless declaration.is_a?(RBS::AST::Declarations::Class) && @super_classes.include?(path)

        updated.update(super_class: nil)
      end
    end

    private

      # The type parameters of a class or module, and whether it names a superclass.
      def index_shape(declaration, path)
        @type_params[path] = declaration.type_params unless declaration.type_params.empty?
        @super_classes << path if declaration.is_a?(RBS::AST::Declarations::Class) && declaration.super_class
      end

      def given_way_members(declaration, path)
        declaration.members.filter_map do |member|
          next if VARIABLES.any? { |klass| member.is_a?(klass) }
          next if declared?(member, path)

          RbsSupport.container?(member) ? give_way([member], path).first : member
        end
      end

      def declared?(member, path)
        keys =
          case member
          when RBS::AST::Members::MethodDefinition then [[path, member.singleton?, member.name]]
          # Rails 8.1 renamed Relation#klass to #model and kept `alias klass model`:
          # the alias defines a method rigor-activerecord already declares.
          when RBS::AST::Members::Alias then [RbsSupport.method_key(path, member, member.new_name)]
          when *ATTRIBUTES then RbsSupport.attribute_names(member).map do |name|
            RbsSupport.method_key(path, member, name)
          end
          else []
          end
        keys.any? { |key| @method_keys.include?(key) }
      end
  end
end
