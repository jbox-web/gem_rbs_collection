# frozen_string_literal: true

# A name declared once: within a gem, across the gems of a run, and against
# the RBS of the gems a run does not regenerate.
module RbsSupport
  module_function

  # Drops the declarations RBS would reject as duplicated — and with them the
  # whole file, which rigor then quarantines. The Rails source defines some
  # constants twice (in both branches of an `if` or a `rescue`), or under a name
  # that is also a class, and a few names as a module in one branch and a class
  # in the other (Rails::TestUnit::TestParser, `if defined?(Prism)`);
  # `rbs prototype` copies each definition. A class or module wins over a
  # constant, and the first declaration over the next ones.
  def dedupe(declarations, containers, namespace = [], seen = Set.new)
    declarations.filter_map do |declaration|
      if constant?(declaration)
        deduped_constant(declaration, containers, namespace, seen)
      elsif container?(declaration)
        deduped_container(declaration, containers, namespace, seen)
      else
        declaration
      end
    end
  end

  # Dedupes the gems generated this run across each other and against
  # `existing`, the RBS of the gems this run does not regenerate: a name they
  # declare is not declared again, as it would not be in a run regenerating
  # every gem. Within the run, the first gem wins — Rails first.
  def dedupe_across(generated, existing)
    containers = container_names(existing)
    generated.each_value { |declarations| container_names(declarations, [], containers) }
    seen = Set.new(constant_paths(existing))
    generated.transform_values { |declarations| dedupe(declarations, containers, [], seen) }
  end

  # The RBS files of this repository a run reads, given the gems it regenerates
  # (name → MAJOR.MINOR directory): the hand-written ones, and the generated
  # ones of the other gems. A regenerated gem's other version directories are
  # left out — the previous version's RBS would collide with the new one
  # (`::Sidekiq::VERSION` in 8.1 and in 8.2).
  def repository_signatures(root, targets)
    gems  = File.join(root, 'gems', '')
    files = Dir.glob(File.join(gems, '*', '*', '*.rbs')).reject { |file| other_version?(file, gems, targets) }
    hand_written, generated = files.partition { |file| !file.end_with?('-generated.rbs') }
    regenerated = targets.map { |gem, directory| File.join(gems, gem, directory, "#{gem}-generated.rbs") }
    [hand_written, generated - regenerated]
  end

  def deduped_constant(declaration, containers, namespace, seen)
    path = qualified(namespace, declaration.name)
    return if containers.key?(path) || seen.include?(path)

    seen << path
    declaration
  end

  def deduped_container(declaration, containers, namespace, seen)
    path = qualified(namespace, declaration.name)
    return unless containers[path] == declaration.class

    declaration.update(members: dedupe(declaration.members, containers, path, seen))
  end

  def other_version?(file, gems, targets)
    gem, directory = file.delete_prefix(gems).split('/')
    targets.key?(gem) && targets[gem] != directory
  end

  private_class_method :deduped_constant, :deduped_container, :other_version?
end
