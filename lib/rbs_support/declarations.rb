# frozen_string_literal: true

module RbsSupport
  CONTAINERS = [RBS::AST::Declarations::Class, RBS::AST::Declarations::Module].freeze
  CONSTANTS  = [
    RBS::AST::Declarations::Constant, RBS::AST::Declarations::ClassAlias, RBS::AST::Declarations::ModuleAlias,
  ].freeze
  VARIABLES = [
    RBS::AST::Members::InstanceVariable, RBS::AST::Members::ClassInstanceVariable, RBS::AST::Members::ClassVariable,
  ].freeze
  MIXINS     = [RBS::AST::Members::Include, RBS::AST::Members::Extend, RBS::AST::Members::Prepend].freeze
  ATTRIBUTES = [
    RBS::AST::Members::AttrReader, RBS::AST::Members::AttrWriter, RBS::AST::Members::AttrAccessor,
  ].freeze

  UNTYPED = RBS::Types::Bases::Any.new(location: nil)

  module_function

  def parse(source)
    _, _, declarations = RBS::Parser.parse_signature(source)
    declarations
  end

  def container?(node)
    CONTAINERS.any? { |klass| node.is_a?(klass) }
  end

  def constant?(node)
    CONSTANTS.any? { |klass| node.is_a?(klass) }
  end

  # The path of a class, module or constant declared under `namespace`. An
  # absolute name — every name, once resolved — already carries its own path.
  def qualified(namespace, name)
    segments = name.to_s.delete_prefix('::').split('::')
    name.to_s.start_with?('::') ? segments : namespace + segments
  end

  # The name a declaration gives, under `namespace` (an RBS::Namespace); none
  # for a global.
  def declaration_name(declaration, namespace)
    case declaration
    when RBS::AST::Declarations::ClassAlias, RBS::AST::Declarations::ModuleAlias
      declaration.new_name.with_prefix(namespace)
    when RBS::AST::Declarations::Global then nil
    else declaration.name.with_prefix(namespace)
    end
  end

  # The key of a method member: `[path, singleton?, name]`.
  def method_key(path, member, name = member.name)
    [path, member.kind == :singleton, name]
  end

  # The method names an `attr_*` member defines.
  def attribute_names(member)
    reader = member.is_a?(RBS::AST::Members::AttrWriter) ? [] : [member.name]
    writer = member.is_a?(RBS::AST::Members::AttrReader) ? [] : [:"#{member.name}="]
    reader + writer
  end

  # The keys of the methods a `def` or an `attr_*` member defines.
  def defined_method_keys(member, path)
    case member
    when RBS::AST::Members::MethodDefinition then [[path, member.singleton?, member.name]]
    when *ATTRIBUTES then attribute_names(member).map { |name| method_key(path, member, name) }
    else []
    end
  end

  # Maps each class or module path to the kind of its first declaration.
  def container_names(declarations, namespace = [], names = {})
    declarations.each do |declaration|
      next unless container?(declaration)

      path = qualified(namespace, declaration.name)
      names[path] ||= declaration.class
      container_names(declaration.members, path, names)
    end
    names
  end

  # The paths of the constants, class aliases and module aliases declared.
  def constant_paths(declarations, namespace = [], paths = [])
    declarations.each do |declaration|
      if constant?(declaration)
        paths << qualified(namespace, declaration_name(declaration, RBS::Namespace.empty))
      elsif container?(declaration)
        constant_paths(declaration.members, qualified(namespace, declaration.name), paths)
      end
    end
    paths
  end

  # `paths` are directories, searched for `.rbs` files, or files.
  def rbs_files(paths)
    paths.flat_map { |path| File.file?(path) ? [path] : Dir.glob(File.join(path, '**/*.rbs')) }
  end
end
