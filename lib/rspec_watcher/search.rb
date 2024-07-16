require 'json'

module RSpecWatcher::Search
  class << self
    def specs_with_matching_constants_in(paths)
      constant_definitions = extract_constant_definitions(Array(paths))
      pattern = constant_definitions.flat_map { |constant|
        [
          constant,
          constant_to_snake_case(constant),
          constant_to_kebab_case(constant)
        ]
      }.uniq.join('|')

      puts "Finding specs for: #{pattern}"

      search_for_specs(pattern)
    end

    def search_for_specs(pattern)
      # TODO: validate terminal escaping here..
      results = if `which rg`.empty?
                  pattern = pattern.gsub('|', '\|')
                  `grep -ril --include '*_spec.rb' "#{pattern}" .`
                else
                  `rg -li --mmap --glob '*_spec.rb' "#{pattern}"`
                end
      results.split("\n").map(&:strip)
    end

    # TODO: add some known specializations. Factories/factory references,
    # routes, etc.
    def extract_constant_definitions(paths)
      paths.flatten.filter_map { |path|
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
