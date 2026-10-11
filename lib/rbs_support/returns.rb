# frozen_string_literal: true

# The return types `rigor sig-gen` infers, written over the `untyped` ones of
# `rbs prototype`'s skeleton.
module RbsSupport
  module_function

  # Indexes the single-overload methods of `declarations` by
  # `[namespace, singleton?, method name]`, keeping only typed returns.
  def typed_returns(declarations, namespace = [], index = {})
    declarations.each do |declaration|
      next unless container?(declaration)

      path = namespace + declaration.name.to_s.delete_prefix('::').split('::')
      declaration.members.each { |member| index_typed_return(member, path, index) }
      typed_returns(declaration.members, path, index)
    end
    index
  end

  # `declarations` with the returns of `returns` (from typed_returns) replacing
  # their `untyped` ones.
  def merge_returns(declarations, returns, namespace = [])
    declarations.map do |declaration|
      next declaration unless container?(declaration)

      path = namespace + declaration.name.to_s.delete_prefix('::').split('::')
      declaration.update(members: declaration.members.map { |member| merged_member(member, returns, path) })
    end
  end

  def index_typed_return(member, path, index)
    return unless member.is_a?(RBS::AST::Members::MethodDefinition) && member.overloads.size == 1

    returns = member.overloads.first.method_type.type.return_type
    index[[path, member.singleton?, member.name]] = returns unless returns.is_a?(RBS::Types::Bases::Any)
  end

  def merged_member(member, returns, path)
    case member
    when RBS::AST::Members::MethodDefinition then retype(member, returns[[path, member.singleton?, member.name]])
    when *CONTAINERS then merge_returns([member], returns, path).first
    else member
    end
  end

  def retype(method, typed)
    return method if typed.nil? || method.overloads.size != 1

    overload    = method.overloads.first
    method_type = overload.method_type
    return method unless method_type.type.return_type.is_a?(RBS::Types::Bases::Any)

    retyped = method_type.update(type: method_type.type.with_return_type(typed))
    method.update(overloads: [overload.update(method_type: retyped)])
  end

  private_class_method :index_typed_return, :merged_member, :retype
end
