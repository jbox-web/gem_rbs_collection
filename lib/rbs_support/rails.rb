# frozen_string_literal: true

# What the Rails gems need beyond their source: the class methods Railties
# forward to their instance, and the core classes their top level reopens.
module RbsSupport
  # Classes whose class methods forward to their singleton instance through
  # `method_missing`: Rails::Railtie's singleton sends to `instance` any method
  # the instance responds to (railtie.rb), so `MyEngine.routes` is
  # `MyEngine.instance.routes`. No reading of the source can see it; their public
  # instance methods are declared on the class as well.
  FORWARDED_TO_INSTANCE = [['Rails', 'Railtie'], ['Rails', 'Engine'], ['Rails', 'Application']].freeze

  # The core classes a gem's generated RBS must not reopen. `rbs prototype`
  # attributes to Object what a file does at its top level — money-rails'
  # `ActiveSupport.on_load(:action_view) { include MoneyRails::ActionViewExtension }`
  # becomes `class Object; include …; end`, a recursive ancestor that takes
  # Object, Class and every class down (RBS::RecursiveAncestorError) — and the
  # polyfills a gem defines for old Rubies (mobility's Object#ruby2_keywords)
  # would leak into every object.
  CORE_REOPENINGS = [['Object'], ['BasicObject'], ['Kernel'], ['Module'], ['Class']].freeze

  module_function

  # Copies, as singleton methods, the public instance methods `paths` declare —
  # those after a `private` marker, or declared private, are left out, as are
  # names the class already declares as singleton methods.
  def mirror_instance_methods(declarations, paths, namespace = [])
    declarations.map do |declaration|
      next declaration unless container?(declaration)

      path    = qualified(namespace, declaration.name)
      members = mirror_instance_methods(declaration.members, paths, path)
      members += mirrored(members) if paths.include?(path)
      declaration.update(members: members)
    end
  end

  def drop_core_reopenings(declarations)
    declarations.reject do |declaration|
      container?(declaration) && CORE_REOPENINGS.include?(qualified([], declaration.name))
    end
  end

  def mirrored(members)
    singletons = members.grep(RBS::AST::Members::MethodDefinition).select(&:singleton?).map(&:name)
    public_instance_methods(members).filter_map do |member|
      next if singletons.include?(member.name) || member.name == :initialize

      member.update(kind: :singleton)
    end
  end

  # The instance methods neither after a `private` marker nor declared private.
  def public_instance_methods(members)
    private = false
    members.select do |member|
      private = true if member.is_a?(RBS::AST::Members::Private)
      private = false if member.is_a?(RBS::AST::Members::Public)
      member.is_a?(RBS::AST::Members::MethodDefinition) && member.kind == :instance &&
        !private && member.visibility != :private
    end
  end

  private_class_method :mirrored, :public_instance_methods
end
