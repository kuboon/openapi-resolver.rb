module OpenapiResolver
  # subset of https://api.rubyonrails.org/classes/ActionDispatch/Request.html
  Request = Data.define(:method, :path, :get, :post) do
    def initialize(method:, path:, get: {}, post: nil) = super

    def GET = get

    def POST = post
  end
end
