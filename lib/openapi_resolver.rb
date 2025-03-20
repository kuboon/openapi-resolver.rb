require "forwardable"
require "pathname"
require "uri"
require "yaml"

module OpenapiResolver
  autoload :VERSION, "openapi_resolver/version"
  autoload :Request, "openapi_resolver/request"
  autoload :Response, "openapi_resolver/response"
  autoload :Error, "openapi_resolver/error"
  autoload :Loader, "openapi_resolver/loader"
  autoload :DocPointer, "openapi_resolver/doc_pointer"
  autoload :RootDoc, "openapi_resolver/root_doc"
  autoload :PathItem, "openapi_resolver/path_item"
  autoload :Operation, "openapi_resolver/operation"
  autoload :Docs, "openapi_resolver/docs"

  def self.new(loader: Loader.new)
    Docs.new(loader:)
  end
end
