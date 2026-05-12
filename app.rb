require "dotenv/load"
require "aws-sdk-s3"
require "rack"
require "securerandom"
require "uri"

class FileToS3App
  def call(env)
    req = Rack::Request.new(env)

    case [req.request_method, req.path_info]
    in ["POST", "/upload"]
      handle_upload(req)
    in ["GET", "/"]
      serve_index
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

    key = build_object_key(filename)
    content_type = uploaded[:type].to_s
    bucket = ENV.fetch("AWS_S3_BUCKET")

    s3_client.put_object(
      bucket: bucket,
      key: key,
      body: tempfile,
      content_type: content_type.empty? ? "application/octet-stream" : content_type
    )

    url = s3_object_url(bucket:, key:)
    update_index_html(url)
    text_response(200, url)
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

  def index_html_path
    File.join(__dir__, "public", "index.html")
  end

  def update_index_html(url)
    File.write(index_html_path, <<~HTML)
      <!DOCTYPE html>
      <html>
      <head><title>Downloading...</title></head>
      <body>
      <script>window.location.href = #{url.to_json};</script>
      <p>Downloading... <a href=#{url.to_json}>click here if it doesn't start</a></p>
      </body>
      </html>
    HTML
  end

  def serve_index
    path = index_html_path
    html = File.exist?(path) ? File.read(path) : "<html><body><p>No file uploaded yet.</p></body></html>"
    [200, { "content-type" => "text/html; charset=utf-8" }, [html]]
  end

  def s3_object_url(bucket:, key:)
    encoded_key = key.split("/").map { |segment| URI::DEFAULT_PARSER.escape(segment) }.join("/")
    "https://#{bucket}.s3.#{ENV.fetch("AWS_REGION")}.amazonaws.com/#{encoded_key}"
  end
end
