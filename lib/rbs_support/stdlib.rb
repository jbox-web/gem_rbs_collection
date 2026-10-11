# frozen_string_literal: true

module RbsSupport
  # Standard libraries loaded to resolve the names the generated RBS refers to.
  RESOLUTION_LIBRARIES = [
    'base64', 'benchmark', 'bigdecimal', 'cgi', 'date', 'delegate', 'did_you_mean', 'digest', 'erb', 'fileutils',
    'forwardable', 'json', 'logger', 'minitest', 'monitor', 'mutex_m', 'openssl', 'pathname', 'pstore', 'ripper',
    'securerandom', 'singleton', 'socket', 'stringio', 'tempfile', 'time', 'timeout', 'tsort', 'uri', 'yaml', 'zlib',
  ].freeze

  # The standard libraries a gem's generated RBS refers to, for its
  # `manifest.yaml`: `rbs collection` loads only the libraries a manifest
  # lists, and a mixin it cannot find fails the class
  # (RBS::NoMixinFoundError on `extend ::Forwardable`).
  module Stdlib
    module_function

    # Maps each top-level name a standard library declares beyond core
    # (`Forwardable`, `JSON`) to that library. A library loading another declares
    # its names too: a name goes to the library declaring the fewest.
    def roots(libraries)
      core     = top_level_names(RBS::Environment.from_loader(RBS::EnvironmentLoader.new))
      declared = libraries.uniq.to_h { |library| [library, library_names(library) - core] }
      declared.sort_by { |library, names| [-names.size, library] }.each_with_object({}) do |(library, names), roots|
        names.each { |name| roots[name] = library }
      end
    end

    # The libraries — given `roots` — whose top-level names the declarations
    # refer to.
    def dependencies(declarations, roots)
      names = Set.new
      declarations.each { |declaration| referenced_names(declaration, names) }
      names.filter_map { |name| roots[name.to_s.delete_prefix('::').split('::').first] }.uniq.sort
    end

    def library_names(library)
      loader = RBS::EnvironmentLoader.new
      return Set.new unless loader.has_library?(library: library, version: nil)

      loader.add(library: library, version: nil)
      top_level_names(RBS::Environment.from_loader(loader))
    end

    def top_level_names(env)
      names = [env.class_decls, env.interface_decls, env.type_alias_decls, env.class_alias_decls].flat_map(&:keys)
      Set.new(names.select { |name| name.namespace.path.empty? }.map { |name| name.name.to_s })
    end

    def referenced_names(node, names)
      case node
      when *CONTAINERS
        superclass_names(node, names)
        node.members.each { |member| referenced_names(member, names) }
      when RBS::AST::Members::MethodDefinition then method_type_names(node, names)
      when *MIXINS then mixin_names(node, names)
      when *ATTRIBUTES, RBS::AST::Declarations::Constant then type_names(node.type, names)
      end
    end

    def method_type_names(method, names)
      method.overloads.each { |overload| overload.method_type.each_type { |type| type_names(type, names) } }
    end

    def mixin_names(mixin, names)
      names << mixin.name
      mixin.args.each { |arg| type_names(arg, names) }
    end

    def superclass_names(node, names)
      return unless node.is_a?(RBS::AST::Declarations::Class) && node.super_class

      names << node.super_class.name
      node.super_class.args.each { |arg| type_names(arg, names) }
    end

    def type_names(type, names)
      names << type.name if type.respond_to?(:name) && type.name.is_a?(RBS::TypeName)
      type.each_type { |inner| type_names(inner, names) } if type.respond_to?(:each_type)
    end

    private_class_method :library_names, :top_level_names, :referenced_names, :method_type_names, :mixin_names,
                         :superclass_names, :type_names
  end
end
