require 'json'

module RSpecWatcher::Rg
  class << self
    def find_matching_specs(paths)
      constant_definitions = extract_constant_definitions(paths)
      pattern = constant_definitions.flat_map { |constant|
        [
          constant,
          constant_to_snake_case(constant),
          constant_to_kebab_case(constant)
        ]
      }.uniq.join('|')

      puts "Finding specs for: #{pattern}"

      `rg -i --mmap --json --glob '*_spec.rb' "#{pattern}"`
        .split("\n")
        .map { |r| JSON.parse(r) }
        .filter_map { |r| r.dig("data", "path", "text") }
        .uniq
    end

    # TODO: add some known specializations. Factories/factory references,
    # routes, etc.
    def extract_constant_definitions(paths)
      puts paths
      paths.filter_map { |path|
        File.read(path).scan(/(?:class|module) (?:.+::)?([A-Z]\w+)(?: <)?/)
      }.flatten.uniq
    end

    def constant_to_snake_case(constant)
      constant.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '')
    end

    def constant_to_kebab_case(constant)
      constant_to_snake_case(constant).gsub(/_/, '-')
    end
  end
end
