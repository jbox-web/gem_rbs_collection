# frozen_string_literal: true

# Reading and writing the files a run produces.
module RbsSupport
  MACRO_SECTIONS = ['macros', 'extended'].freeze

  module_function

  # Writes `path` through a temporary file of the same directory renamed over
  # it: an interrupted run leaves the previous file whole, never a truncated one.
  def write_atomically(path, &)
    temporary = "#{path}.#{Process.pid}.tmp"
    File.open(temporary, 'w', &)
    File.rename(temporary, path)
  ensure
    FileUtils.rm_f(temporary)
  end

  # Merges the `<gem>-macros.yml` indexes MacroIndex wrote: a macro two gems
  # define keeps the union of their effects.
  def merged_macro_indexes(files)
    files.each_with_object({ 'macros' => {}, 'extended' => {} }) do |file, merged|
      index = YAML.load_file(file) || {}
      MACRO_SECTIONS.each do |section|
        (index[section] || {}).each do |name, effect|
          merged[section][name] = MacroIndex.merge(merged[section].fetch(name, {}), effect)
        end
      end
    end
  end
end
