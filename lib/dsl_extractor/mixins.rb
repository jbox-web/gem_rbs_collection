# frozen_string_literal: true

class DslExtractor
  # What reaches a class through a mixin: `include` / `extend`, the Rails load
  # hooks, the gem macros MacroIndex recorded, and the concerns written by hand.
  module Mixins
    # Where a `include X` / `extend X` lands, by [mode, keyword]:
    #
    # - in an `included` block, `extend X` reaches the including class's
    #   singleton — so does an `include X` of the concern's ClassMethods — and
    #   `include X` reaches its instances, as an `include X` of the concern does;
    # - in a `class_methods` block, `include X` adds to ClassMethods;
    # - in a class or module body, it is recorded only with `mixins: true`:
    #   `rbs prototype` already writes it for the gems.
    MIXIN_OWNERS = {
      %i[included extend]       => :class_methods,
      %i[class_methods include] => :class_methods,
      %i[included include]      => :itself,
      %i[body include]          => :mixins,
      %i[body extend]           => :mixins,
      %i[on_load include]       => :itself,
      %i[on_load extend]        => :itself,
    }.freeze

    # The Rails load hooks and the class each one runs in. A gem extends Rails
    # this way — `ActiveSupport.on_load(:active_record) { extend X; include Y }`
    # is `ActiveRecord::Base.extend(X)` — at the top of a file or inside an
    # engine's initializer, so the whole tree is searched.
    LOAD_HOOKS = {
      active_record:     ['ActiveRecord', 'Base'],
      action_view:       ['ActionView', 'Base'],
      action_controller: ['ActionController', 'Base'],
      action_mailer:     ['ActionMailer', 'Base'],
      active_job:        ['ActiveJob', 'Base'],
    }.freeze

    private

      def mixin_call(node, path, mode, _constants)
        mixin(node, path, mode)
        extend_hook(node, path, mode) if node.name == :extend
      end

      # `extend FriendlyId` runs FriendlyId.extended(model), which extends Base
      # and includes Model: MacroIndex records what each `self.extended` does.
      def extend_hook(node, path, mode)
        call_arguments(node).each do |argument|
          effect = @hooks["::#{constant_path(argument).join('::')}"]
          apply_effect(effect, path, mode) if effect
        end
      end

      def mixin(node, path, mode)
        owner = mixin_owner(MIXIN_OWNERS[[mode, node.name]], path)
        return if owner.nil?

        target = %i[body on_load].include?(mode) && node.name == :extend ? @extends : @includes
        call_arguments(node).each do |argument|
          name = constant_path(argument)
          target[owner] << name.join('::') unless name.empty?
        end
      end

      def mixin_owner(rule, path)
        case rule
        when :class_methods then path + ['ClassMethods']
        when :itself then path
        when :mixins then (path if @mixins)
        end
      end

      def on_load_blocks(root)
        Prism::Pattern.new('CallNode[name: :on_load]').scan(root).each do |call|
          target = load_hook_target(call)
          next unless target

          @kinds[target.first(1)] ||= RBS::AST::Declarations::Module
          @kinds[target]          ||= RBS::AST::Declarations::Class
          visit_body(call.block.body, target, :on_load, {})
        end
      end

      def load_hook_target(call)
        return unless constant_path(call.receiver) == ['ActiveSupport'] && call.block.is_a?(Prism::BlockNode)

        LOAD_HOOKS[literal(call_arguments(call).first)&.to_sym]
      end

      # A gem macro called in a class body, from MacroIndex: the modules it
      # includes or extends, and the method it defines under the name its first
      # argument gives (`pg_search_scope :search_by_name`).
      def gem_macro(node, path, mode, _constants)
        effect = @macros[node.name.to_s]
        return if effect.nil?

        apply_effect(effect, path, mode)
        name = literal(call_arguments(node).first)&.to_sym
        argument_methods(effect, name, path, mode) if name
        accessors_from_arguments(node, path, mode, effect['accessors_from_arguments'])
        effect.fetch('instance_suffixes', []).each do |suffix|
          add(path, mode, false, :"#{name}#{suffix}", :any) if name
        end
      end

      def argument_methods(effect, name, path, mode)
        add(path, mode, true, name, :any) if effect['singleton_from_argument']
        add(path, mode, false, name, :any) if effect['instance_from_argument']
      end

      # `virtual_attributes :total_price, :customer_name` — an accessor per argument.
      def accessors_from_arguments(node, path, mode, kind)
        return unless kind

        names, = arguments(node, {})
        accessors(path, mode, names, kind)
      end

      def apply_effect(effect, path, mode)
        effect.fetch('include', []).each { |name| @includes[path] << name }
        effect.fetch('extend', []).each { |name| extension_target(path, mode) << name }
        effect.fetch('singleton_methods', []).each { |name| add(path, mode, true, name.to_sym, :any) }
        effect.fetch('instance_methods', []).each { |name| add(path, mode, false, name.to_sym, :any) }
      end

      # In a concern's blocks, an `extend` reaches the class through ClassMethods.
      def extension_target(path, mode)
        CLASS_LEVEL.include?(mode) ? @includes[path + ['ClassMethods']] : @extends[path]
      end
  end
end
