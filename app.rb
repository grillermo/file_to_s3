require "dotenv/load"
require "fileutils"
require "json"
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
      serve_index(req)
    in ["GET" | "HEAD", path] if path.start_with?("/files/")
      serve_file(path.delete_prefix("/files/"), head: req.request_method == "HEAD")
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

    filename = build_local_filename(uploaded[:filename])
    FileUtils.mkdir_p(files_dir)

    uploaded[:tempfile].rewind
    File.open(File.join(files_dir, filename), "wb") do |file|
      IO.copy_stream(uploaded[:tempfile], file)
    end

    text_response(200, file_url(req, filename))
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

  def build_local_filename(filename)
    "#{SecureRandom.uuid}-#{filename}"
  end

  def sanitize_filename(filename)
    return nil if filename.to_s.strip.empty?

    File.basename(filename).gsub(/[^\w.\-]/, "_")
  end

  # Overridable so tests can point at a scratch directory instead of the
  # repo's real files/.
  def files_dir
    ENV.fetch("FILES_DIR") { File.join(__dir__, "files") }
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

  def latest_filename
    Dir.children(files_dir)
      .map { |name| File.join(files_dir, name) }
      .select { |path| File.file?(path) }
      .max_by { |path| File.mtime(path) }
      &.then { |path| File.basename(path) }
  end

  def serve_index(req)
    filename = File.directory?(files_dir) ? latest_filename : nil
    return [200, { "content-type" => "text/html; charset=utf-8" }, ["<html><body><p>No file uploaded yet.</p></body></html>"]] unless filename

    url = file_url(req, filename)
    html = <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Downloading...</title></head>
      <body>
      <script>window.location.href = #{url.to_json};</script>
      <p>Downloading... <a href=#{url.to_json}>click here if it doesn't start</a></p>
      </body>
      </html>
    HTML
    [200, { "content-type" => "text/html; charset=utf-8" }, [html]]
  end

  # iOS's install daemon issues HEAD (and Range) for the OTA manifest and the
  # .ipa before it downloads either, so HEAD must answer with the same status
  # and headers as GET — just without the body.
  def serve_file(filename, head: false)
    safe_name = File.basename(filename)
    path = File.join(files_dir, safe_name)

    return not_found unless File.file?(path)

    content_type = Rack::Mime.mime_type(File.extname(safe_name), "application/octet-stream")
    headers = {
      "content-type" => content_type,
      "content-length" => File.size(path).to_s
    }

    return [200, headers, []] if head

    [200, headers, [File.binread(path)]]
  end

  def file_url(req, filename)
    "#{req.base_url}/files/#{URI::DEFAULT_PARSER.escape(filename)}"
  end
end
