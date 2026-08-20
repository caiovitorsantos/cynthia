class TemplateRenderer
  MissingVariableError = Class.new(StandardError)

  def self.call(template, variables)
    variables = variables.to_h.stringify_keys

    template.body.gsub(Template::VARIABLE_PATTERN) do
      key = Regexp.last_match(1)
      variables.fetch(key) { raise MissingVariableError, "Variável não preenchida: #{key}" }
    end
  end
end
