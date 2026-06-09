require "dotenv/load"
require "aws-sdk-s3"
require "fileutils"
require "rack"
require "securerandom"
require "uri"

class FileToS3App
  def call(env)
    req = Rack::Request.new(env)

    case [req.request_method, req.path_info]
    in ["POST", "/upload"]
      return unauthorized unless authenticated?(req)

      handle_upload(req)
    in ["POST", "/receive"]
      return unauthorized unless authenticated?(req)

      handle_receive(req)
    in ["GET", "/"]
      serve_index
    in ["GET", "/proof"]
      text_response(200, "hola arturo!")
    else
      not_found
    end
  rescue StandardError => e
    error_page(e)
  end

  private

  def authenticated?(req)
    bearer_token(req) == ENV.fetch("AUTH_TOKEN")
  end

  def bearer_token(req)
    req.get_header("HTTP_AUTHORIZATION").to_s[/\ABearer\s+(.+)\z/, 1]
  end

  def handle_upload(req)
    uploaded = extract_uploaded_file(req)
    return uploaded unless uploaded.is_a?(Hash)

    key = build_object_key(uploaded[:filename])
    content_type = uploaded[:content_type].to_s
    bucket = ENV.fetch("AWS_S3_BUCKET")

    s3_client.put_object(
      bucket: bucket,
      key: key,
      body: uploaded[:tempfile],
      content_type: content_type.empty? ? "application/octet-stream" : content_type
    )

    url = s3_object_url(bucket:, key:)
    update_index_html(url)
    text_response(200, url)
  end

  def handle_receive(req)
    uploaded = extract_uploaded_file(req)
    return uploaded unless uploaded.is_a?(Hash)

    path = File.join(files_dir, build_local_filename(uploaded[:filename]))
    FileUtils.mkdir_p(files_dir)

    uploaded[:tempfile].rewind
    File.open(path, "wb") do |file|
      IO.copy_stream(uploaded[:tempfile], file)
    end

    text_response(200, path)
  end

  def extract_uploaded_file(req)
    uploaded = req.params["file"]

    return unprocessable("Missing multipart file field 'file'.") unless uploaded.is_a?(Hash)

    tempfile = uploaded[:tempfile]
    filename = sanitize_filename(uploaded[:filename])

    return unprocessable("The uploaded file payload was invalid.") unless tempfile && filename

    size = tempfile.size
    return unprocessable("The file is empty.") if size.zero?

    {
      tempfile: tempfile,
      filename: filename,
      content_type: uploaded[:type]
    }
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

  def build_local_filename(filename)
    "#{SecureRandom.uuid}-#{filename}"
  end

  def sanitize_filename(filename)
    return nil if filename.to_s.strip.empty?

    File.basename(filename).gsub(/[^\w.\-]/, "_")
  end

  def files_dir
    File.join(__dir__, "files")
  end

  def text_response(status, body)
    [status, { "content-type" => "text/plain; charset=utf-8" }, [body]]
  end

  def unprocessable(message)
    text_response(422, message)
  end

  def unauthorized
    [
      401,
      {
        "content-type" => "text/plain; charset=utf-8",
        "www-authenticate" => %(Bearer realm="file-to-s3")
      },
      ["Unauthorized"]
    ]
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
