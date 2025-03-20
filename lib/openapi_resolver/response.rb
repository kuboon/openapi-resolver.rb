module OpenapiResolver
  # subset of https://api.rubyonrails.org/classes/ActionDispatch/Response.html
  Response = Data.define(:status, :parsed_body)
end
