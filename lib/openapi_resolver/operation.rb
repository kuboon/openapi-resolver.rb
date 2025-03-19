class OpenapiResolver
  class Operation
    def initialize(doc_pointer)
      @doc_pointer = doc_pointer
    end

    def each_schema(request:, response:, &block)
      req_schema = request_body_schema(has_body: request.POST && !request.POST.empty?)
      if req_schema
        yield @doc_pointer.doc.merge("$id" => @doc_pointer.uri.to_s), req_schema, request.POST, "request body"
      end

      res_schema = response_schema(status: response.status)
      if res_schema
        yield @doc_pointer.doc.merge("$id" => @doc_pointer.uri.to_s), res_schema, response.parsed_body, "response body"
      end
    rescue => e
      raise Error.wrap(e).add_message(method: @doc_pointer.segments.last)
    end

    private

    def content_type = "application/json"

    def request_body_schema(has_body:)
      req_body = @doc_pointer["requestBody"]
      return if !has_body && !req_body
      raise Error.new("missing requestBody schema") unless req_body
      unless has_body
        raise Error.new("request body required") if req_body["required"]
      end
      # return if content_type == 'application/x-www-form-urlencoded' # rspec
      raise Error.new("unknown content-type #{content_type}") unless req_body.dig("content", content_type)
      schema = req_body.dig("content", content_type, "schema")
      raise Error.new("missing schema for #{content_type}") unless schema
      @doc_pointer.dig_new("requestBody", "content", content_type, "schema").fragment
    end

    def response_schema(status:)
      resp = @doc_pointer["responses"][status.to_s]
      raise Error.new("unknown response code #{status}") unless resp
      content = resp["content"]
      return if content.nil?
      unless content[content_type]
        Rails.logger.warn "unknown content-type #{content_type} for #{status} at #{@method} #{@path}"
        return
      end
      schema = content[content_type]["schema"]
      raise Error.new("missing schema") unless schema
      @doc_pointer.dig_new("responses", status, "content", content_type, "schema").fragment
    end
  end
end
