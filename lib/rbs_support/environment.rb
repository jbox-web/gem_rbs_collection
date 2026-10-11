# frozen_string_literal: true

# The RBS environments names are resolved against, built tolerantly.
module RbsSupport
  module_function

  # Builds the environment the names are resolved against: core, the standard
  # libraries, the `--defer-to` and `--resolve-with` RBS, and the given
  # sources — one per gem, keyed by a buffer name. Tolerantly: the `sig/` the
  # bundled gems ship do not all load together (anthropic's declares
  # Anthropic::BedrockClient twice).
  def resolution_environment(sources, directories)
    tolerant_environment(libraries: RESOLUTION_LIBRARIES, directories: [], files: rbs_files(directories),
                         sources: sources)
  end

  # The same environment for a project's own RBS, which may not build cleanly:
  # a declaration RBS rejects as duplicated is skipped — the rest of its file
  # still loads, as rigor does — rather than failing the whole environment.
  # `libraries` are standard libraries, `directories` load strictly, `files` and
  # `sources` (buffer name → declarations) tolerantly; what a source loses is
  # named on stderr.
  def tolerant_environment(libraries:, directories:, files:, sources:)
    env = RBS::Environment.from_loader(environment_loader(libraries, directories))
    files.each { |file| add_file_tolerantly(env, file) }
    sources.each do |name, declarations|
      rejected = add_tolerantly(env, RBS::Buffer.new(name: name, content: ''), [], declarations)
      rejected.each { |rejection| warn "#{name}: dropped #{rejection}, already declared differently" }
    end
    env.resolve_type_names
  end

  # Adds `declarations`, each top-level one minus what collides
  # (CollisionFilter), and returns the names dropped.
  def add_tolerantly(env, buffer, directives, declarations)
    declarations.each_with_object([]) do |declaration, rejected|
      filter = CollisionFilter.new(env)
      kept   = filter.call([declaration])
      rejected.concat(filter.rejected)
      add_source_tolerantly(env, RBS::Source::RBS.new(buffer, directives, kept), rejected) unless kept.empty?
    end
  end

  # What an `rbs collection` lockfile installs: the directory of each gem served
  # by a git or local source, and the standard libraries it declares. The gems
  # that ship their own `sig/` (source `rubygems`) are left out — resolving them
  # would need the bundle loaded.
  def collection_signatures(lockfile)
    lock    = YAML.load_file(lockfile)
    root    = File.expand_path(lock.fetch('path'), File.dirname(lockfile))
    by_type = lock.fetch('gems').group_by { |gem| gem.dig('source', 'type') }
    [installed_directories(root, by_type), by_type.fetch('stdlib', []).map { |gem| gem.fetch('name') }]
  end

  def environment_loader(libraries, directories)
    loader = RBS::EnvironmentLoader.new
    libraries.uniq.each do |library|
      loader.add(library: library, version: nil) if loader.has_library?(library: library, version: nil)
    end
    directories.each { |directory| loader.add(path: Pathname(directory)) if File.exist?(directory) }
    loader
  end

  def add_file_tolerantly(env, file)
    buffer = RBS::Buffer.new(name: file, content: File.read(file, encoding: 'UTF-8'))
    _, directives, declarations = RBS::Parser.parse_signature(buffer)
    add_tolerantly(env, buffer, directives, declarations)
  end

  def add_source_tolerantly(env, source, rejected)
    env.add_source(source)
  rescue RBS::DuplicatedDeclarationError => e
    # A source RBS rejects stays in `env.sources` — add_source records it
    # before inserting — and `resolve_type_names`, which rebuilds the
    # environment from the sources, would raise on it again.
    env.sources.delete(source)
    rejected << e.name.to_s
  end

  def installed_directories(root, by_type)
    (by_type.fetch('git', []) + by_type.fetch('local', [])).map do |gem|
      File.join(root, gem.fetch('name'), gem.fetch('version').to_s)
    end
  end

  private_class_method :environment_loader, :add_file_tolerantly, :add_source_tolerantly, :installed_directories
end
