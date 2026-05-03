require "dotenv/load"
require "aws-sdk-s3"
require "rack"
require "securerandom"
require "uri"

class FileToS3App
  MAX_FILE_SIZE = 25 * 1024 * 1024

  def call(env)
    req = Rack::Request.new(env)

    case [req.request_method, req.path_info]
    in ["POST", "/upload"]
      handle_upload(req)
    else
      not_found
    end
  rescue StandardError => e
    error_page(e)
  end

  private

  def handle_upload(req)
    uploaded = req.params["file"]

    return unprocessable("Missing multipart file field 'file'.") unless uploaded.is_a?(Hash)

    tempfile = uploaded[:tempfile]
    filename = sanitize_filename(uploaded[:filename])

    return unprocessable("The uploaded file payload was invalid.") unless tempfile && filename

    size = tempfile.size
    return unprocessable("The file is empty.") if size.zero?
    return unprocessable("Files larger than #{MAX_FILE_SIZE / (1024 * 1024)} MB are not allowed.") if size > MAX_FILE_SIZE

    key = build_object_key(filename)
    content_type = uploaded[:type].to_s
    bucket = ENV.fetch("AWS_S3_BUCKET")

    s3_client.put_object(
      bucket: bucket,
      key: key,
      body: tempfile,
      content_type: content_type.empty? ? "application/octet-stream" : content_type
    )

    text_response(200, s3_object_url(bucket:, key:))
  end

  def s3_client
    @s3_client ||= Aws::S3::Client.new(
      region: ENV.fetch("AWS_REGION"),
      credentials: Aws::Credentials.new(
        ENV.fetch("AWS_CLIENT_ID"),
        ENV.fetch("AWS_SECRET")
      )
    )
  end

  def build_object_key(filename)
    prefix = ENV.fetch("AWS_S3_PREFIX", "uploads").sub(%r{/\z}, "")
    [prefix, "#{SecureRandom.uuid}-#{filename}"].reject(&:empty?).join("/")
  end

  def sanitize_filename(filename)
    return nil if filename.to_s.strip.empty?

    File.basename(filename).gsub(/[^\w.\-]/, "_")
  end

  def text_response(status, body)
    [status, { "content-type" => "text/plain; charset=utf-8" }, [body]]
  end

  def unprocessable(message)
    text_response(422, message)
  end

  def not_found
    text_response(404, "Not found")
  end

  def error_page(error)
    warn "[file-to-s3] #{error.class}: #{error.message}"
    text_response(500, error.message)
  end

  def s3_object_url(bucket:, key:)
    encoded_key = key.split("/").map { |segment| URI::DEFAULT_PARSER.escape(segment) }.join("/")
    "https://#{bucket}.s3.#{ENV.fetch("AWS_REGION")}.amazonaws.com/#{encoded_key}"
  end
end
